import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let captionInputRequested = Notification.Name("captionInputRequested")
    static let clipboardImageChanged = Notification.Name("clipboardImageChanged")
    static let compressionStarted = Notification.Name("compressionStarted")
    static let compressionProgressUpdated = Notification.Name("compressionProgressUpdated")
    static let uploadStarted = Notification.Name("uploadStarted")
    static let uploadProgressUpdated = Notification.Name("uploadProgressUpdated")
    static let uploadFinished = Notification.Name("uploadFinished")
    static let shortcutUploadRequested = Notification.Name("shortcutUploadRequested")
    static let settingsUpdated = Notification.Name("settingsUpdated")
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let openHistoryRequested = Notification.Name("openHistoryRequested")
}

struct StatusItemPipelineProgress: Equatable {
    enum Stage: Equatable {
        case idle
        case compression
        case upload
    }

    private(set) var stage: Stage = .idle
    private(set) var usesCompression = false
    private(set) var compressionFraction = 0.0
    private(set) var uploadFraction = 0.0

    var activeFraction: Double {
        switch stage {
        case .idle:
            return 0
        case .compression:
            return compressionFraction
        case .upload:
            return uploadFraction
        }
    }

    mutating func beginCompression() {
        stage = .compression
        usesCompression = true
        compressionFraction = 0
        uploadFraction = 0
    }

    mutating func updateCompression(_ fraction: Double) {
        guard stage == .compression else { return }
        compressionFraction = Self.clamped(fraction)
    }

    mutating func beginUpload(afterCompression: Bool) {
        stage = .upload
        usesCompression = afterCompression
        compressionFraction = afterCompression ? 1 : 0
        uploadFraction = 0
    }

    mutating func updateUpload(_ fraction: Double) {
        guard stage == .upload else { return }
        uploadFraction = Self.clamped(fraction)
    }

    mutating func reset() {
        self = StatusItemPipelineProgress()
    }

    private static func clamped(_ fraction: Double) -> Double {
        min(1, max(0, fraction.isFinite ? fraction : 0))
    }
}

/// 自定义状态栏视图负责拖放；标准 `NSStatusBarButton` 本身没有可配置的拖放回调。
/// 除普通文件 URL 外，还注册 Photos 等来源使用的公开文件承诺类型。
final class StatusItemDropView: NSView {
    var onMenuRequested: (() -> Void)?
    var onPasteboardDropped: ((NSPasteboard) -> Void)?

    private var isDragTarget = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }
        registerForDraggedTypes([.fileURL] + promiseTypes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onMenuRequested?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragTarget = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragTarget
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { isDragTarget = false }
        guard canAccept(sender.draggingPasteboard) else { return false }
        onPasteboardDropped?(sender.draggingPasteboard)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isDragTarget {
            NSColor.selectedControlColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
    }

    private func updateDragTarget(for pasteboard: NSPasteboard) -> Bool {
        let canAccept = canAccept(pasteboard)
        isDragTarget = canAccept
        return canAccept
    }

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        if !PasteboardFileResolver.regularFileURLs(in: pasteboard).isEmpty {
            return true
        }

        return !PasteboardFileResolver.filePromiseReceivers(in: pasteboard).isEmpty
    }
}

@main
struct Pic2LinkApp: App {
    @StateObject private var viewModel = MainViewModel.shared
    @StateObject private var localization = LocalizationManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                    openSettings()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
        .commandsRemoved()

        Settings {
            SettingsView(
                settings: viewModel.appSettings,
                onSave: { settings in
                    viewModel.saveSettings(settings)
                },
                onValidate: { profile in
                    try await viewModel.validateProfile(profile)
                }
            )
            .environment(\.locale, localization.locale)
            .environment(\.layoutDirection, localization.layoutDirection)
            .frame(width: 780, height: 620)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
#if DEBUG
    private var settingsTestWindow: NSWindow?
#endif
    var statusItem: NSStatusItem?
    var pasteboardMonitor: PasteboardMonitor?
    var statusMenu: NSMenu?
    var menuHostingView: NSHostingView<AnyView>?
    var statusDropView: StatusItemDropView?
    private var historyWindow: NSWindow?

    private let viewModel = MainViewModel.shared
    private let localization = LocalizationManager.shared
    private let uploadingStatusItemLength: CGFloat = 72
    private let twoStageStatusItemLength: CGFloat = 82
    private var statusItemProgress = StatusItemPipelineProgress()
    private var hotKeyRef: EventHotKeyRef?
    private var selectedPhotosHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var livePhotoLibraryPicker: LivePhotoLibraryPicker?
    private let uploadHotKeyID: UInt32 = 1
    private let selectedPhotosHotKeyID: UInt32 = 2
    private let promisedFileQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-storeScreenshots") {
            Task { @MainActor in await StoreScreenshotRenderer.run() }
            return
        }
#endif
        NSApp.setActivationPolicy(.accessory)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-openSettingsForUITesting") {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-AppleInterfaceStyle"), index + 1 < args.count {
                NSApp.appearance = NSAppearance(named: args[index + 1] == "Dark" ? .darkAqua : .aqua)
            }
            // Exercise the real settings view without relying on a zero-size
            // SwiftUI scene appearing or writing the user's saved configuration.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: SettingsView(
                settings: .default, onSave: { _ in }, onValidate: { _ in false }
            ).environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .frame(width: 780, height: 620))
            settingsTestWindow = window
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-captionForUITesting") {
            CaptionUITestHarness.shared.start()
            return
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
#endif

        setupStatusMenu()
        DispatchQueue.main.async { [weak self] in
            self?.installStatusBarEntry()
        }
        setupPasteboardMonitoring()
        registerGlobalShortcut()
        setupObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        promisedFileQueue.cancelAllOperations()
        if let statusItem {
            statusItem.menu = nil
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        unregisterGlobalShortcut()
    }

    private func installStatusBarEntry() {
        guard statusItem == nil, statusMenu != nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        statusItem = item

        guard let button = item.button else { return }
        viewModel.attachCaptionPrompt(to: button)

        let dropView = StatusItemDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onMenuRequested = { [weak self] in
            self?.showStatusMenu()
        }
        dropView.onPasteboardDropped = { [weak self] pasteboard in
            self?.handleDroppedPasteboard(pasteboard)
        }
        button.addSubview(dropView)
        statusDropView = dropView

        configureStatusItemForIdleState()
    }

    private func setupStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let contentView = localizedContentView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 500)

        statusMenu = menu
        menuHostingView = hostingView
        rebuildMenuItems()
    }

    private func rebuildMenuItems() {
        guard let menu = statusMenu, let hostingView = menuHostingView else { return }
        menu.removeAllItems()

        hostingView.rootView = localizedContentView()

        let contentItem = NSMenuItem()
        contentItem.view = hostingView
        menu.addItem(contentItem)

        menu.addItem(.separator())

        let uploadTitle = L10n.tr("menu.uploadClipboard", viewModel.uploadShortcut.displayString)
        let uploadItem = NSMenuItem(title: uploadTitle, action: #selector(handleShortcutUpload), keyEquivalent: "")
        uploadItem.target = self
        menu.addItem(uploadItem)

        let selectedPhotosItem = NSMenuItem(title: L10n.tr("selection.menu"),
            action: #selector(handleSelectedPhotosUpload), keyEquivalent: "")
        selectedPhotosItem.target = self
        selectedPhotosItem.identifier = NSUserInterfaceItemIdentifier("menu.uploadSelection")
        menu.addItem(selectedPhotosItem)

        let fileUploadItem = NSMenuItem(title: L10n.tr("menu.uploadFile"), action: #selector(handleManualFileUpload), keyEquivalent: "")
        fileUploadItem.target = self
        menu.addItem(fileUploadItem)

        let livePhotoUploadItem = NSMenuItem(
            title: L10n.tr("menu.uploadLivePhoto"),
            action: #selector(handlePhotoLibraryLivePhotoUpload),
            keyEquivalent: ""
        )
        livePhotoUploadItem.target = self
        menu.addItem(livePhotoUploadItem)

        menu.addItem(.separator())

        let captionItem = NSMenuItem(
            title: L10n.tr("caption.enabled"),
            action: #selector(toggleCaptionBeforeUpload),
            keyEquivalent: ""
        )
        captionItem.target = self
        captionItem.state = viewModel.appSettings.captionBeforeUpload ? .on : .off
        captionItem.identifier = NSUserInterfaceItemIdentifier("menu.caption")
        menu.addItem(captionItem)

        let markdownItem = NSMenuItem(
            title: L10n.tr("menu.markdownLinks"),
            action: #selector(toggleMarkdownLinks),
            keyEquivalent: ""
        )
        markdownItem.target = self
        markdownItem.state = viewModel.appSettings.copyLinksAsMarkdown ? .on : .off
        markdownItem.identifier = NSUserInterfaceItemIdentifier("menu.markdownLinks")
        menu.addItem(markdownItem)

        let compressionItem = NSMenuItem(
            title: L10n.tr("settings.compression"),
            action: #selector(toggleUploadCompression),
            keyEquivalent: ""
        )
        compressionItem.target = self
        compressionItem.state = viewModel.appSettings.uploadCompression.isEnabled ? .on : .off
        menu.addItem(compressionItem)

        let livePhotoGIFItem = NSMenuItem(
            title: L10n.tr("settings.livePhotoGIF"),
            action: #selector(toggleLivePhotoGIFConversion),
            keyEquivalent: ""
        )
        livePhotoGIFItem.target = self
        livePhotoGIFItem.state = viewModel.appSettings.uploadCompression.convertClipboardLivePhotosToGIF ? .on : .off
        menu.addItem(livePhotoGIFItem)

        menu.addItem(.separator())

        let switchItem = NSMenuItem(title: L10n.tr("menu.switchProfile"), action: nil, keyEquivalent: "")
        let switchMenu = NSMenu(title: L10n.tr("menu.switchProfile"))
        for profile in viewModel.profiles {
            let item = NSMenuItem(title: profile.displayName, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.state = profile.id == viewModel.activeProfileID ? .on : .off
            item.representedObject = profile.id.uuidString
            switchMenu.addItem(item)
        }
        switchItem.submenu = switchMenu
        menu.addItem(switchItem)

        let settingsItem = NSMenuItem(title: L10n.tr("menu.settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func setupPasteboardMonitoring() {
        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor?.startMonitoring()
        pasteboardMonitor?.imageChanged = { image in
            var userInfo: [String: Any] = [:]
            if let image {
                userInfo["image"] = image
            }
            NotificationCenter.default.post(name: .clipboardImageChanged, object: nil, userInfo: userInfo)
        }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleCaptionInputRequested), name: .captionInputRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutUpload), name: .shortcutUploadRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCompressionStarted), name: .compressionStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCompressionProgressUpdated(_:)), name: .compressionProgressUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadStarted(_:)), name: .uploadStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadProgressUpdated(_:)), name: .uploadProgressUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadFinished), name: .uploadFinished, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsUpdated), name: .settingsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHistoryRequested), name: .openHistoryRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChanged), name: .languageChanged, object: nil)
    }

    @objc private func handleSettingsUpdated() {
        registerGlobalShortcut()
        rebuildMenuItems()
    }

    @objc private func handleLanguageChanged() {
        updateStatusItem()
        viewModel.clearTransientStatus()
        rebuildMenuItems()
        refreshHistoryWindow()
    }

    private func registerGlobalShortcut() {
        unregisterGlobalShortcut()

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.id == appDelegate.uploadHotKeyID {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .shortcutUploadRequested, object: nil)
                    }
                    return noErr
                }

                if hotKeyID.id == appDelegate.selectedPhotosHotKeyID {
                    DispatchQueue.main.async {
                        appDelegate.handleSelectedPhotosUpload()
                    }
                    return noErr
                }

                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandler
        )

        guard installStatus == noErr else { return }

        let selectionShortcut = KeyboardShortcut.selectedPhotos
        let selectionStatus = RegisterEventHotKey(selectionShortcut.key.keyCode, selectionShortcut.carbonModifiers,
            EventHotKeyID(signature: fourCharCode(from: "P2LK"), id: selectedPhotosHotKeyID),
            GetApplicationEventTarget(), 0, &selectedPhotosHotKeyRef)
        if selectionStatus != noErr {
            viewModel.statusMessage = L10n.tr("selection.shortcutUnavailable")
            NotificationManager.shared.sendErrorNotification(message: viewModel.statusMessage)
        }
        let shortcut = viewModel.uploadShortcut
        guard shortcut != selectionShortcut else {
            viewModel.statusMessage = L10n.tr("selection.shortcutReserved")
            return
        }
        let hotKeyID = EventHotKeyID(signature: fourCharCode(from: "P2LK"), id: uploadHotKeyID)
        RegisterEventHotKey(
            shortcut.key.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterGlobalShortcut() {
        if let selectedPhotosHotKeyRef {
            UnregisterEventHotKey(selectedPhotosHotKeyRef)
            self.selectedPhotosHotKeyRef = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
    }

    @objc private func handleShortcutUpload() {
        Task { @MainActor in
            await viewModel.uploadClipboardImage()
        }
    }

    @objc private func handleSelectedPhotosUpload() {
        let foreground = NSWorkspace.shared.frontmostApplication
        let bundleID = foreground?.bundleIdentifier
        let processIdentifier = foreground?.processIdentifier
        statusMenu?.cancelTracking()
        Task { @MainActor in
            await viewModel.uploadSelectedPhotos(applicationBundleID: bundleID, processIdentifier: processIdentifier)
        }
    }

    @objc private func handleManualFileUpload() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("filePicker.title")
        panel.message = L10n.tr("filePicker.message")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        Task { @MainActor in
            await viewModel.uploadFile(at: fileURL)
        }
    }

    @objc private func handlePhotoLibraryLivePhotoUpload() {
        statusMenu?.cancelTracking()
        let picker = LivePhotoLibraryPicker()
        livePhotoLibraryPicker = picker
        picker.present { [weak self] result in
            guard let self else { return }
            self.livePhotoLibraryPicker = nil
            switch result {
            case .success(let assetIdentifier):
                Task { @MainActor in
                    await self.viewModel.uploadLivePhotoFromLibrary(assetIdentifier: assetIdentifier)
                }
            case .failure(.cancelled):
                break
            case .failure(let error):
                self.viewModel.statusMessage = L10n.tr("status.livePhotoConversionFailed", error.localizedDescription)
            }
        }
    }

    @objc private func toggleCaptionBeforeUpload() {
        viewModel.setCaptionBeforeUploadEnabled(!viewModel.appSettings.captionBeforeUpload)
    }

    @objc private func toggleMarkdownLinks() {
        viewModel.setCopyLinksAsMarkdown(!viewModel.appSettings.copyLinksAsMarkdown)
    }

    @objc private func handleCaptionInputRequested() {
        statusMenu?.cancelTracking()
    }

    @objc private func toggleUploadCompression() {
        let isEnabled = viewModel.appSettings.uploadCompression.isEnabled
        viewModel.setUploadCompressionEnabled(!isEnabled)
    }

    @objc private func toggleLivePhotoGIFConversion() {
        let isEnabled = viewModel.appSettings.uploadCompression.convertClipboardLivePhotosToGIF
        viewModel.setLivePhotoGIFConversionEnabled(!isEnabled)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw) else { return }
        viewModel.selectProfile(id: id)
        rebuildMenuItems()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    @objc private func handleHistoryRequested() {
        statusMenu?.cancelTracking()
        showHistoryWindow()
    }

    private func showHistoryWindow() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.tr("history.title")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 460, height: 360)
            window.contentView = NSHostingView(rootView: historyContentView())
            window.center()
            historyWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshHistoryWindow() {
        guard let historyWindow else { return }
        historyWindow.title = L10n.tr("history.title")
        historyWindow.contentView = NSHostingView(rootView: historyContentView())
    }

    private func historyContentView() -> AnyView {
        AnyView(
            HistoryWindowView(viewModel: viewModel)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
        )
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showStatusMenu() {
        guard let statusItem, let statusMenu, let button = statusItem.button else { return }
        rebuildMenuItems()
        statusItem.menu = statusMenu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func handleDroppedPasteboard(_ pasteboard: NSPasteboard) {
        let fileURLs = PasteboardFileResolver.regularFileURLs(in: pasteboard)
        if !fileURLs.isEmpty {
            Task { @MainActor [weak self] in
                await self?.viewModel.uploadFiles(at: fileURLs)
            }
            return
        }

        receivePromisedFiles(from: pasteboard)
    }

    private func receivePromisedFiles(from pasteboard: NSPasteboard) {
        let receivers = PasteboardFileResolver.filePromiseReceivers(in: pasteboard)
        guard !receivers.isEmpty else { return }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Pic2Link-Dropped-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            viewModel.statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
            return
        }

        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: destination,
                options: [:],
                operationQueue: promisedFileQueue
            ) { [weak self] fileURL, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.viewModel.statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
                    } else {
                        await self.viewModel.uploadFile(at: fileURL)
                    }
                }
            }
        }
    }

    @objc private func handleUploadStarted(_ notification: Notification) {
        let didCompress = notification.userInfo?["didCompress"] as? Bool ?? false
        statusItemProgress.beginUpload(afterCompression: didCompress)
        updateStatusItem()
    }

    @objc private func handleCompressionStarted() {
        statusItemProgress.beginCompression()
        updateStatusItem()
    }

    @objc private func handleCompressionProgressUpdated(_ notification: Notification) {
        statusItemProgress.updateCompression(progress(from: notification))
        updateStatusItem()
    }

    @objc private func handleUploadProgressUpdated(_ notification: Notification) {
        statusItemProgress.updateUpload(progress(from: notification))
        updateStatusItem()
    }

    private func progress(from notification: Notification) -> Double {
        notification.userInfo?["progress"] as? Double ?? 0
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        guard statusItemProgress.stage != .idle else {
            configureStatusItemForIdleState()
            return
        }

        let activePercent = Int((statusItemProgress.activeFraction * 100).rounded())
        let itemLength = statusItemProgress.usesCompression
            ? twoStageStatusItemLength
            : uploadingStatusItemLength
        statusItem?.length = itemLength
        button.title = "\(activePercent)%"
        button.imagePosition = .imageLeading

        if statusItemProgress.usesCompression {
            button.image = makeTwoStageProgressIcon(
                compression: statusItemProgress.compressionFraction,
                upload: statusItemProgress.uploadFraction,
                activeStage: statusItemProgress.stage
            )
            let compressionPercent = Int((statusItemProgress.compressionFraction * 100).rounded())
            let uploadPercent = Int((statusItemProgress.uploadFraction * 100).rounded())
            button.toolTip = "\(L10n.tr("clipboard.compressionProgress")) \(compressionPercent)% → \(L10n.tr("clipboard.uploadProgress")) \(uploadPercent)%"
        } else {
            button.image = makeStatusIcon(systemName: "arrow.up.circle.fill")
            button.toolTip = "\(L10n.tr("clipboard.uploadProgress")) \(activePercent)%"
        }
    }

    @objc private func handleUploadFinished() {
        statusItemProgress.reset()
        configureStatusItemForIdleState()
        rebuildMenuItems()
    }

    private func configureStatusItemForIdleState() {
        guard let button = statusItem?.button else { return }
        statusItem?.length = NSStatusItem.squareLength
        button.title = ""
        button.imagePosition = .imageOnly
        button.highlight(false)
        button.image = makeStatusIcon(systemName: "photo.on.rectangle")
        button.toolTip = L10n.tr("statusItem.tooltip")
    }

    private func makeStatusIcon(systemName: String) -> NSImage? {
        let icon = NSImage(systemSymbolName: systemName, accessibilityDescription: "Pic2Link")
        icon?.isTemplate = true
        return icon
    }

    private func makeTwoStageProgressIcon(
        compression: Double,
        upload: Double,
        activeStage: StatusItemPipelineProgress.Stage
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 16), flipped: false) { _ in
            self.drawProgressRing(
                center: NSPoint(x: 6, y: 8),
                fraction: compression,
                isActive: activeStage == .compression
            )

            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: 13, y: 5.5))
            chevron.line(to: NSPoint(x: 15.5, y: 8))
            chevron.line(to: NSPoint(x: 13, y: 10.5))
            chevron.lineWidth = 1.4
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(0.72).setStroke()
            chevron.stroke()

            self.drawProgressRing(
                center: NSPoint(x: 22, y: 8),
                fraction: upload,
                isActive: activeStage == .upload
            )
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pic2Link"
        return image
    }

    private func drawProgressRing(center: NSPoint, fraction: Double, isActive: Bool) {
        let clampedFraction = min(1, max(0, fraction))
        let radius: CGFloat = 4.5
        let trackRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let track = NSBezierPath(ovalIn: trackRect)
        track.lineWidth = 1.3
        NSColor.black.withAlphaComponent(0.24).setStroke()
        track.stroke()

        if clampedFraction > 0 {
            let progress = NSBezierPath()
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - (360 * clampedFraction),
                clockwise: true
            )
            progress.lineWidth = 2
            progress.lineCapStyle = .round
            NSColor.black.setStroke()
            progress.stroke()
        }

        if isActive {
            let dotRadius: CGFloat = 1.15
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            NSColor.black.setFill()
            dot.fill()
        }
    }

    private func localizedContentView() -> AnyView {
        AnyView(
            ContentView()
                .environmentObject(viewModel)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .id(localization.currentLanguage.rawValue)
        )
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.button?.highlight(false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenuItems()
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var clipboardImage: NSImage?
    @State private var pasteboardMonitor: PasteboardMonitor?

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ClipboardImageSection(
                        image: clipboardImage,
                        activeUploadImage: viewModel.activeUploadPreviewImage,
                        activeUploadFileName: viewModel.activeUploadFileName,
                        isPipelineActive: viewModel.isUploadPipelineActive,
                        captionStatus: viewModel.captionStatus,
                        isCompressing: viewModel.isCompressing,
                        compressionProgress: viewModel.compressionProgress,
                        didCompressActiveUpload: viewModel.didCompressActiveUpload,
                        isUploading: viewModel.isUploading,
                        uploadProgress: viewModel.uploadProgress,
                        pendingUploadCount: viewModel.pendingUploadCount,
                        shortcutLabel: viewModel.uploadShortcut.displayString,
                        onUpload: {
                            Task {
                                await viewModel.uploadClipboardImage()
                            }
                        }
                    )

                    Divider()

                    UploadedImagesSection(
                        images: viewModel.displayedImages,
                        hasMore: viewModel.hasMoreImages,
                        onCopyURL: { image in
                            viewModel.copyImageURL(image)
                        },
                        onDelete: { id in
                            viewModel.deleteImage(id: id)
                        },
                        onViewMore: {
                            NotificationCenter.default.post(name: .openHistoryRequested, object: nil)
                        },
                        onClearAll: {
                            viewModel.clearAllImages()
                        }
                    )

                    Divider()

                    SettingsButtonSection(
                        activeProfile: viewModel.activeProfile
                    )
                }
                .padding()
            }
        }
        .frame(width: 360, height: 500)
        .onAppear {
            setupPasteboardMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            openSettings()
        }
        .onDisappear {
            pasteboardMonitor?.stopMonitoring()
        }
    }

    private func setupPasteboardMonitoring() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-storeScreenshots") {
            clipboardImage = StoreScreenshotRenderer.sampleImage
            return
        }
#endif
        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor?.startMonitoring()
        pasteboardMonitor?.refresh()
        clipboardImage = pasteboardMonitor?.currentImage

        NotificationCenter.default.addObserver(forName: .clipboardImageChanged, object: nil, queue: .main) { notification in
            clipboardImage = notification.userInfo?["image"] as? NSImage
        }

        NotificationCenter.default.addObserver(forName: .settingsUpdated, object: nil, queue: .main) { _ in
            clipboardImage = pasteboardMonitor?.currentImage
        }
    }
}

private func fourCharCode(from string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
