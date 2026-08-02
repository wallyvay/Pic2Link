import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let clipboardImageChanged = Notification.Name("clipboardImageChanged")
    static let uploadStarted = Notification.Name("uploadStarted")
    static let uploadProgressUpdated = Notification.Name("uploadProgressUpdated")
    static let uploadFinished = Notification.Name("uploadFinished")
    static let shortcutUploadRequested = Notification.Name("shortcutUploadRequested")
    static let settingsUpdated = Notification.Name("settingsUpdated")
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
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
                .onAppear {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-openSettingsForUITesting") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            openSettings()
                        }
                    }
#endif
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
    var statusItem: NSStatusItem?
    var pasteboardMonitor: PasteboardMonitor?
    var statusMenu: NSMenu?
    var menuHostingView: NSHostingView<AnyView>?

    private let viewModel = MainViewModel.shared
    private let localization = LocalizationManager.shared
    private let defaultStatusItemLength: CGFloat = 28
    private let uploadingStatusItemLength: CGFloat = 72
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let uploadHotKeyID: UInt32 = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPasteboardMonitoring()
        setupStatusMenu()
        registerGlobalShortcut()
        setupObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalShortcut()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: defaultStatusItemLength)

        guard let button = statusItem?.button else {
            return
        }

        configureButtonForIdleState(button)
        button.toolTip = L10n.tr("statusItem.tooltip")

        let dropView = StatusBarDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onActivateMenu = { [weak self] in
            self?.presentStatusMenu()
        }
        dropView.onDroppedFile = { fileURL in
            Task { @MainActor in
                await MainViewModel.shared.uploadFile(at: fileURL)
            }
        }
        dropView.onImageDropped = { image in
            Task { @MainActor in
                await MainViewModel.shared.uploadImage(image)
            }
        }
        dropView.onDragStateChanged = { [weak self] isTargeted in
            self?.updateDragAppearance(isTargeted: isTargeted)
        }
        button.addSubview(dropView)
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
        uploadItem.isEnabled = !viewModel.isUploading
        menu.addItem(uploadItem)

        let fileUploadItem = NSMenuItem(title: L10n.tr("menu.uploadFile"), action: #selector(handleManualFileUpload), keyEquivalent: "")
        fileUploadItem.target = self
        fileUploadItem.isEnabled = !viewModel.isUploading
        menu.addItem(fileUploadItem)

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

    private func presentStatusMenu() {
        guard let menu = statusMenu, let button = statusItem?.button else { return }
        rebuildMenuItems()
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func setupPasteboardMonitoring() {
        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor?.startMonitoring()
        pasteboardMonitor?.imageChanged = { image in
            if let image {
                NotificationCenter.default.post(name: .clipboardImageChanged, object: nil, userInfo: ["image": image])
            }
        }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutUpload), name: .shortcutUploadRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadStarted), name: .uploadStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadProgressUpdated(_:)), name: .uploadProgressUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleUploadFinished), name: .uploadFinished, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsUpdated), name: .settingsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageChanged), name: .languageChanged, object: nil)
    }

    @objc private func handleSettingsUpdated() {
        registerGlobalShortcut()
        rebuildMenuItems()
    }

    @objc private func handleLanguageChanged() {
        statusItem?.button?.toolTip = L10n.tr("statusItem.tooltip")
        viewModel.clearTransientStatus()
        rebuildMenuItems()
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

                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandler
        )

        guard installStatus == noErr else { return }

        let shortcut = viewModel.uploadShortcut
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

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func handleUploadStarted() {
        guard let button = statusItem?.button else { return }
        statusItem?.length = uploadingStatusItemLength
        button.title = "0%"
        button.imagePosition = .imageLeading
        button.image = makeStatusIcon(systemName: "arrow.up.circle.fill")
    }

    @objc private func handleUploadProgressUpdated(_ notification: Notification) {
        guard let button = statusItem?.button else { return }
        let progress = notification.userInfo?["progress"] as? Double ?? 0
        let percent = max(0, min(100, Int(progress * 100)))
        button.title = "\(percent)%"
    }

    @objc private func handleUploadFinished() {
        guard let button = statusItem?.button else { return }
        configureButtonForIdleState(button)
        rebuildMenuItems()
    }

    private func updateDragAppearance(isTargeted: Bool) {
        guard let button = statusItem?.button else { return }
        guard !viewModel.isUploading else { return }
        button.highlight(isTargeted)
        button.image = makeStatusIcon(systemName: isTargeted ? "photo.badge.plus" : "photo.on.rectangle")
    }

    private func configureButtonForIdleState(_ button: NSStatusBarButton) {
        statusItem?.length = defaultStatusItemLength
        button.title = ""
        button.imagePosition = .imageOnly
        button.highlight(false)
        button.image = makeStatusIcon(systemName: "photo.on.rectangle")
    }

    private func makeStatusIcon(systemName: String) -> NSImage? {
        let icon = NSImage(systemSymbolName: systemName, accessibilityDescription: "Pic2Link")
        icon?.isTemplate = true
        return icon
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
}

final class StatusBarDropView: NSView {
    var onImageDropped: ((NSImage) -> Void)?
    var onDroppedFile: ((URL) -> Void)?
    var onActivateMenu: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    override func mouseDown(with event: NSEvent) {
        onActivateMenu?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivateMenu?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard extractDroppedItem(from: sender.draggingPasteboard) != nil else {
            onDragStateChanged?(false)
            return []
        }

        onDragStateChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragStateChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        extractDroppedItem(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let item = extractDroppedItem(from: sender.draggingPasteboard) else {
            onDragStateChanged?(false)
            return false
        }

        onDragStateChanged?(false)
        switch item {
        case .image(let image):
            onImageDropped?(image)
        case .file(let fileURL):
            onDroppedFile?(fileURL)
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragStateChanged?(false)
    }

    private func extractDroppedItem(from pasteboard: NSPasteboard) -> DroppedItem? {
        if let image = NSImage(pasteboard: pasteboard) {
            return .image(image)
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL),
                   let decoded = fileURLString.removingPercentEncoding,
                   let url = URL(string: decoded),
                   url.isFileURL {
                    if let image = NSImage(contentsOf: url) {
                        return .image(image)
                    }
                    return .file(url)
                }
            }
        }

        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return .image(image)
            }
        }

        return nil
    }
}

private enum DroppedItem {
    case image(NSImage)
    case file(URL)
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
                        isUploading: viewModel.isUploading,
                        uploadProgress: viewModel.uploadProgress,
                        shortcutLabel: viewModel.uploadShortcut.displayString,
                        onUpload: {
                            Task {
                                if let clipboardImage {
                                    await viewModel.uploadImage(clipboardImage)
                                }
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
                        onViewMore: {},
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
        pasteboardMonitor = PasteboardMonitor()
        pasteboardMonitor?.startMonitoring()
        pasteboardMonitor?.refresh()
        clipboardImage = pasteboardMonitor?.currentImage

        NotificationCenter.default.addObserver(forName: .clipboardImageChanged, object: nil, queue: .main) { notification in
            if let image = notification.userInfo?["image"] as? NSImage {
                clipboardImage = image
            }
        }

        NotificationCenter.default.addObserver(forName: .settingsUpdated, object: nil, queue: .main) { _ in
            clipboardImage = pasteboardMonitor?.currentImage
        }
    }
}

private func fourCharCode(from string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
