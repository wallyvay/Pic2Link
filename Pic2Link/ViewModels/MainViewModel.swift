import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import Photos

/// 主视图模型
@MainActor
class MainViewModel: ObservableObject {
    static let shared = MainViewModel()
    private let captionPrompt = CaptionPromptController()
    private let captionPreparationQueue = SerialUploadQueue()
    private let linkClipboard: LinkClipboard
    private var isReadingSelection = false
    private let largeFileThreshold: Int64 = 200 * 1024 * 1024

    private let storageService = StorageService.shared
    private let notificationManager = NotificationManager.shared
    private let launchAtLoginService = LaunchAtLoginService.shared
    private lazy var uploadQueue = SerialUploadQueue(
        onPendingCountChanged: { [weak self] count in
            self?.pendingUploadCount = count
        },
        onBecameActive: { [weak self] in
            self?.isUploadPipelineActive = true
            self?.uploadProgress = .zero
            self?.compressionProgress = .zero
        },
        onBecameIdle: { [weak self] in
            self?.isUploadPipelineActive = false
            self?.isCompressing = false
            self?.isUploading = false
            self?.uploadProgress = .zero
            self?.compressionProgress = .zero
            self?.didCompressActiveUpload = false
            self?.activeUploadPreviewImage = nil
            self?.activeUploadFileName = nil
            NotificationCenter.default.post(name: .uploadFinished, object: nil)
        }
    )

    @Published var appSettings: AppSettings
    @Published var uploadedImages: [UploadedImage] = []
    @Published private(set) var isUploadPipelineActive = false
    @Published private(set) var isCompressing = false
    @Published var isUploading = false
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var compressionProgress = ImageCompressionProgress.zero
    @Published private(set) var didCompressActiveUpload = false
    @Published var uploadProgress = UploadProgress.zero
    @Published private(set) var activeUploadPreviewImage: NSImage?
    @Published private(set) var activeUploadFileName: String?
    @Published private(set) var captionStatus: String?
    @Published var statusMessage: String = ""

    let maxDisplayedImages = 10

    convenience init() {
        self.init(linkClipboard: LinkClipboard())
    }

    init(linkClipboard: LinkClipboard) {
        self.linkClipboard = linkClipboard
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-captionForUITesting")
            || ProcessInfo.processInfo.arguments.contains("-openSettingsForUITesting")
            || ProcessInfo.processInfo.arguments.contains("-storeScreenshots")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.appSettings = .default
            return
        }
#endif
        self.appSettings = storageService.appSettings
        self.uploadedImages = storageService.uploadedImages
        notificationManager.requestPermission()
        syncLaunchAtLoginIfNeeded()
    }

    var profiles: [ImageHostProfile] {
        appSettings.profiles
    }

    var activeProfile: ImageHostProfile? {
        appSettings.activeProfile
    }

    var activeProfileID: UUID? {
        get { appSettings.activeProfileID }
        set {
            appSettings.activeProfileID = newValue
            persistSettings()
        }
    }

    var uploadShortcut: KeyboardShortcut {
        appSettings.uploadShortcut
    }

    var activeProfileSummary: String {
        activeProfile?.providerSummary ?? L10n.tr("profile.notConfigured")
    }

    var activeProfileIsConfigured: Bool {
        activeProfile?.isConfigured ?? false
    }

    func attachCaptionPrompt(to view: NSView) { captionPrompt.attach(to: view) }

    private func sourceQueue(captionEnabled: Bool) -> SerialUploadQueue {
        captionEnabled ? captionPreparationQueue : uploadQueue
    }

    /// 上传指定图片
    func uploadImage(_ image: NSImage) async {
        guard let profile = activeProfile else {
            statusMessage = L10n.tr("status.configureFirst")
            return
        }

        guard profile.isConfigured else {
            statusMessage = L10n.tr("status.incompleteConfig")
            return
        }

        do {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
                throw UploadServiceError.invalidConfig
            }

            let compressionSettings = appSettings.uploadCompression
            let captionEnabled = appSettings.captionBeforeUpload
            let tasksAhead = sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self] in
                guard let self else { return }
                await self.performImageUpload(
                    pngData,
                    profile: profile,
                    compressionSettings: compressionSettings,
                    captionEnabled: captionEnabled
                )
            }

            if tasksAhead > 0 {
                statusMessage = L10n.tr("status.uploadQueued", tasksAhead)
            }
        } catch {
            statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
        }
    }

    func uploadClipboardImage() async {
        let compressionSettings = appSettings.uploadCompression
        if compressionSettings.convertClipboardLivePhotosToGIF,
           let livePhotoSource = await ClipboardLivePhotoResolver.firstSource(in: .general) {
            await uploadClipboardLivePhoto(livePhotoSource)
            return
        }

        if let fileURL = PasteboardFileResolver.firstImageFileURL(in: .general) {
            await uploadFile(at: fileURL)
            return
        }

        guard let image = currentClipboardImage() else {
            statusMessage = L10n.tr("status.clipboardEmpty")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        await uploadImage(image)
    }

    /// Explicit Photos-library selection is intentionally separate from clipboard
    /// conversion: Photos copies normally contain only the JPEG/HEIC cover image.
    func uploadLivePhotoFromLibrary(assetIdentifier: String) async {
        guard let profile = activeProfile else {
            statusMessage = L10n.tr("status.configureFirst")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        guard profile.isConfigured else {
            statusMessage = L10n.tr("status.incompleteConfig")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        let captionEnabled = appSettings.captionBeforeUpload
        let tasksAhead = sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self] in
            guard let self else { return }
            await self.performPhotoLibraryLivePhotoUpload(
                assetIdentifier: assetIdentifier,
                profile: profile,
                captionEnabled: captionEnabled
            )
        }

        if tasksAhead > 0 {
            statusMessage = L10n.tr("status.uploadQueued", tasksAhead)
        }
    }

    private func uploadClipboardLivePhoto(_ source: ClipboardLivePhotoSource) async {
        guard let profile = activeProfile else {
            statusMessage = L10n.tr("status.configureFirst")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        guard profile.isConfigured else {
            statusMessage = L10n.tr("status.incompleteConfig")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        let captionEnabled = appSettings.captionBeforeUpload
        let tasksAhead = sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self] in
            guard let self else { return }
            await self.performClipboardLivePhotoUpload(source, profile: profile, captionEnabled: captionEnabled)
        }

        if tasksAhead > 0 {
            statusMessage = L10n.tr("status.uploadQueued", tasksAhead)
        }
    }

    func uploadFile(at fileURL: URL) async {
        guard let profile = activeProfile else {
            statusMessage = L10n.tr("status.configureFirst")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        guard profile.isConfigured else {
            statusMessage = L10n.tr("status.incompleteConfig")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        do {
            let uploadableFile = try UploadableFile(fileURL: fileURL)

            guard profile.provider.supportsArbitraryFiles || uploadableFile.isImage else {
                let message = L10n.tr("status.providerImagesOnly", profile.displayName)
                statusMessage = message
                notificationManager.sendErrorNotification(message: message)
                return
            }

            if uploadableFile.fileSize > largeFileThreshold {
                let confirmed = confirmLargeFileUpload(file: uploadableFile)
                guard confirmed else {
                    statusMessage = L10n.tr("status.largeFileCancelled")
                    return
                }
            }

            let compressionSettings = appSettings.uploadCompression
            let captionEnabled = appSettings.captionBeforeUpload && uploadableFile.isImage
            let tasksAhead = sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self] in
                guard let self else { return }
                await self.performFileUpload(
                    uploadableFile,
                    profile: profile,
                    compressionSettings: compressionSettings,
                    captionEnabled: captionEnabled
                )
            }

            if tasksAhead > 0 {
                statusMessage = L10n.tr("status.uploadQueued", tasksAhead)
            }
        } catch {
            statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
        }
    }

    func uploadFiles(at fileURLs: [URL]) async {
        for fileURL in fileURLs {
            await uploadFile(at: fileURL)
        }
    }

    /// Separate from clipboard upload: capture the foreground target before any prompt.
    func uploadSelectedPhotos(applicationBundleID: String?, processIdentifier: pid_t?) async {
        guard !isReadingSelection else { return }
        guard let applicationBundleID, let application = SelectionApplication(rawValue: applicationBundleID),
              application.isAvailable, let processIdentifier else {
            handleUploadFailure(SelectedPhotoError.unsupportedApplication)
            return
        }
        guard let profile = activeProfile, profile.isConfigured else {
            statusMessage = L10n.tr("status.configureFirst")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }
        let compressionSettings = appSettings.uploadCompression
        let captionEnabled = appSettings.captionBeforeUpload
        isReadingSelection = true
        defer { isReadingSelection = false }
        do {
            let sources = try await Task.detached(priority: .userInitiated) {
                try SelectedPhotoReader.read(from: application, processIdentifier: processIdentifier)
            }.value
            var photoCount = 0
            for source in sources {
                switch source {
                case .file(let url):
                    guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { continue }
                    let access: ScopedFileReadAccess
                    do { access = try SandboxFileAccess.selectedFileAccess(to: url) }
                    catch is CancellationError { photoCount += 1; continue }
                    guard let file = try? UploadableFile(fileURL: url), file.isImage else { continue }
                    photoCount += 1
                    if file.fileSize > largeFileThreshold, !confirmLargeFileUpload(file: file) { continue }
                    sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self, access] in
                        defer { access.finish() }
                        await self?.performFileUpload(file, profile: profile,
                            compressionSettings: compressionSettings, captionEnabled: captionEnabled)
                    }
                case .libraryAsset(let identifier):
                    photoCount += 1
                    sourceQueue(captionEnabled: captionEnabled).enqueue { [weak self] in
                        await self?.performSelectedLibraryPhotoUpload(identifier: identifier, profile: profile,
                            compressionSettings: compressionSettings, captionEnabled: captionEnabled)
                    }
                }
            }
            if photoCount == 0 { throw SelectedPhotoError.noPhotos }
        } catch { handleUploadFailure(error) }
    }

    private func performSelectedLibraryPhotoUpload(identifier: String, profile: ImageHostProfile,
        compressionSettings: UploadCompressionSettings, captionEnabled: Bool) async {
        do {
            let asset = try await PhotoLibraryImageSource.asset(identifier: identifier)
            if asset.playbackStyle == .livePhoto, compressionSettings.convertClipboardLivePhotosToGIF {
                await performPhotoLibraryLivePhotoUpload(assetIdentifier: identifier, profile: profile, captionEnabled: captionEnabled)
                return
            }
            let payload = try await PhotoLibraryImageSource.payload(for: asset)
            await performPayloadUpload(payload, isImage: true, profile: profile,
                compressionSettings: compressionSettings, captionEnabled: captionEnabled)
        } catch { handleUploadFailure(error) }
    }

    private func performImageUpload(
        _ pngData: Data,
        profile: ImageHostProfile,
        compressionSettings: UploadCompressionSettings,
        captionEnabled: Bool
    ) async {
        await performPayloadUpload(
            CaptionUploadPayload(data: pngData, fileName: nil, mimeType: "image/png"),
            isImage: true, profile: profile, compressionSettings: compressionSettings,
            captionEnabled: captionEnabled
        )
    }

    private func performFileUpload(
        _ file: UploadableFile,
        profile: ImageHostProfile,
        compressionSettings: UploadCompressionSettings,
        captionEnabled: Bool
    ) async {
        let access = ScopedFileReadAccess(url: file.fileURL)
        defer { access.finish() }
        do {
            if !captionEnabled { statusMessage = L10n.tr("status.waitingForFile", file.fileName) }
            try await UploadFileReadinessGate().waitUntilReady(fileURL: file.fileURL)
            // Do not map a file that another app has just finished writing. A
            // regular in-memory copy freezes the upload payload before signing.
            let data = try Data(contentsOf: file.fileURL)
            await performPayloadUpload(
                CaptionUploadPayload(data: data, fileName: file.fileName, mimeType: file.mimeType),
                isImage: file.isImage, profile: profile, compressionSettings: compressionSettings,
                captionEnabled: captionEnabled
            )
        } catch {
            handleUploadFailure(error)
        }
    }

    /// All byte-producing entry points meet here, before compression or any network request.
    private func performPayloadUpload(
        _ source: CaptionUploadPayload,
        isImage: Bool,
        profile: ImageHostProfile,
        compressionSettings: UploadCompressionSettings,
        captionEnabled: Bool,
        resetEntry: Bool = true,
        submittedCaption: String? = nil
    ) async {
        if captionEnabled, isImage {
            captionPrompt.present(image: NSImage(data: source.data), fileName: source.fileName) { [weak self] text in
                guard let self, let text else { return }
                self.uploadQueue.enqueue { [weak self] in
                    await self?.performPayloadUpload(
                        source, isImage: isImage, profile: profile,
                        compressionSettings: compressionSettings, captionEnabled: false,
                        submittedCaption: text
                    )
                }
            }
            return
        }
        if resetEntry {
            beginActiveEntry(previewImage: isImage ? NSImage(data: source.data) : nil, fileName: source.fileName)
        }
        let prepared: CaptionUploadPayload
        do {
            defer { captionStatus = nil }
            guard let result = try await CaptionUploadGate.prepare(
                source, enabled: submittedCaption != nil, isImage: isImage,
                requestCaption: { _ in submittedCaption },
                compose: { [self] input, text in
                    captionStatus = L10n.tr("caption.rendering")
                    statusMessage = L10n.tr("caption.rendering")
                    return try await Task.detached(priority: .userInitiated) {
                        try PhotoCaptionRenderer().compose(input, text: text)
                    }.value
                }
            ) else {
                statusMessage = L10n.tr("caption.cancelled")
                return
            }
            prepared = result
        } catch {
            statusMessage = L10n.tr("caption.failed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        var payload = prepared
        if isImage, compressionSettings.isEnabled {
            do {
                let compressed = try await compressForUpload(
                    data: prepared.data, fileName: prepared.fileName, settings: compressionSettings
                )
                payload = CaptionUploadPayload(data: compressed.data, fileName: compressed.fileName, mimeType: compressed.mimeType)
            } catch {
                handleCompressionFailure(error)
                return
            }
        }
        activeUploadPreviewImage = isImage ? NSImage(data: payload.data) : nil
        activeUploadFileName = payload.fileName
        let thumbnail = activeUploadPreviewImage.flatMap { UploadedImage.createThumbnail(from: $0) }
        let service = ImageHostingService(config: profile)
        beginNetworkUpload()
        statusMessage = payload.fileName.map { L10n.tr("status.uploadingFile", $0) }
            ?? L10n.tr("status.uploadingTo", profile.displayName)
        let progressCancellable = observeProgress(from: service)
        defer {
            progressCancellable.cancel()
            isUploading = false
        }
        do {
            let url: String
            if let fileName = payload.fileName {
                url = try await service.uploadFile(payload.data, fileName: fileName, mimeType: payload.mimeType)
            } else {
                url = try await service.uploadImage(payload.data)
            }
            let fileName = payload.fileName ?? url.components(separatedBy: "/").last ?? "image.png"
            let uploadedImage = UploadedImage(fileName: fileName, url: url, thumbnailData: thumbnail, caption: submittedCaption)
            uploadedImages.insert(uploadedImage, at: 0)
            storageService.addUploadedImage(uploadedImage)
            linkClipboard.copy(uploadedImage, asMarkdown: appSettings.copyLinksAsMarkdown, playSound: false)
            notificationManager.sendUploadCompleteNotification(fileName: fileName, imageURL: url)
            statusMessage = L10n.tr("status.uploadSuccess", payload.fileName ?? profile.displayName)
        } catch {
            handleUploadFailure(error)
        }
    }

    private func performClipboardLivePhotoUpload(
        _ source: ClipboardLivePhotoSource,
        profile: ImageHostProfile,
        captionEnabled: Bool
    ) async {
        if !captionEnabled {
            beginActiveEntry(previewImage: NSImage(contentsOf: source.stillImageURL), fileName: source.gifFileName)
        }
        do {
            let gif = try await convertLivePhotoForUpload(
                pairedVideoURL: source.pairedVideoURL,
                gifFileName: source.gifFileName,
                reportsProgress: !captionEnabled
            )
            await performPayloadUpload(
                CaptionUploadPayload(data: gif.data, fileName: gif.fileName ?? source.gifFileName, mimeType: "image/gif"),
                isImage: true, profile: profile, compressionSettings: .default,
                captionEnabled: captionEnabled, resetEntry: false
            )
        } catch {
            if captionEnabled { handleUploadFailure(error) } else { handleLivePhotoConversionFailure(error) }
        }
    }

    private func performPhotoLibraryLivePhotoUpload(
        assetIdentifier: String,
        profile: ImageHostProfile,
        captionEnabled: Bool
    ) async {
        do {
            if !captionEnabled { statusMessage = L10n.tr("status.loadingLivePhoto") }
            let source = try await PhotoLibraryLivePhotoSourceResolver.exportPairedVideo(
                assetIdentifier: assetIdentifier
            )
            defer { source.removeTemporaryFiles() }

            if !captionEnabled { beginActiveEntry(previewImage: nil, fileName: source.gifFileName) }
            let gif = try await convertLivePhotoForUpload(
                pairedVideoURL: source.pairedVideoURL,
                gifFileName: source.gifFileName,
                reportsProgress: !captionEnabled
            )
            await performPayloadUpload(
                CaptionUploadPayload(data: gif.data, fileName: gif.fileName ?? source.gifFileName, mimeType: "image/gif"),
                isImage: true,
                profile: profile,
                compressionSettings: .default,
                captionEnabled: captionEnabled,
                resetEntry: false
            )
        } catch {
            if captionEnabled { handleUploadFailure(error) } else { handleLivePhotoConversionFailure(error) }
        }
    }

    private func beginActiveEntry(previewImage: NSImage?, fileName: String?) {
        captionStatus = nil
        activeUploadPreviewImage = previewImage
        activeUploadFileName = fileName
        compressionProgress = .zero
        uploadProgress = .zero
        didCompressActiveUpload = false
        isCompressing = false
        isUploading = false
    }

    private func compressForUpload(
        data: Data,
        fileName: String?,
        settings: UploadCompressionSettings
    ) async throws -> CompressedUploadImage {
        let status = fileName.map { L10n.tr("status.compressingFile", $0) }
            ?? L10n.tr("status.compressingImage")
        let compressor = UploadImageCompressor()
        return try await runUploadPreparation(status: status) { progress in
            try compressor.compress(
                data: data,
                fileName: fileName,
                settings: settings,
                onProgress: progress
            )
        }
    }

    private func convertLivePhotoForUpload(
        pairedVideoURL: URL,
        gifFileName: String,
        reportsProgress: Bool = true
    ) async throws -> CompressedUploadImage {
        let converter = LivePhotoGIFConverter()
        if !reportsProgress {
            return try await Task.detached(priority: .userInitiated) {
                try await converter.convert(pairedVideoURL: pairedVideoURL, fileName: gifFileName, onProgress: { _ in })
            }.value
        }
        return try await runUploadPreparation(status: L10n.tr("status.convertingLivePhoto")) { progress in
            try await converter.convert(
                pairedVideoURL: pairedVideoURL,
                fileName: gifFileName,
                onProgress: progress
            )
        }
    }

    private func runUploadPreparation(
        status: String,
        work: @escaping @Sendable (UploadImageCompressor.ProgressHandler) async throws -> CompressedUploadImage
    ) async throws -> CompressedUploadImage {
        isCompressing = true
        didCompressActiveUpload = true
        compressionProgress = .zero
        statusMessage = status
        NotificationCenter.default.post(name: .compressionStarted, object: nil)

        defer {
            isCompressing = false
        }

        var streamContinuation: AsyncStream<ImageCompressionProgress>.Continuation?
        let progressStream = AsyncStream<ImageCompressionProgress> { continuation in
            streamContinuation = continuation
        }
        guard let streamContinuation else {
            throw ImageCompressionError.cannotCreateDestination
        }

        let progressTask = Task { @MainActor [weak self] in
            for await progress in progressStream {
                guard let self, self.isCompressing else { continue }
                self.compressionProgress = progress
                NotificationCenter.default.post(
                    name: .compressionProgressUpdated,
                    object: nil,
                    userInfo: ["progress": progress.fractionCompleted]
                )
            }
        }

        let preparationTask = Task.detached(priority: .userInitiated) {
            try await work { progress in
                streamContinuation.yield(progress)
            }
        }

        let result: CompressedUploadImage
        do {
            result = try await preparationTask.value
        } catch {
            streamContinuation.finish()
            await progressTask.value
            throw error
        }

        streamContinuation.finish()
        await progressTask.value

        compressionProgress = ImageCompressionProgress(completedUnits: 1, totalUnits: 1)
        return result
    }

    private func beginNetworkUpload() {
        isUploading = true
        uploadProgress = .zero
        NotificationCenter.default.post(
            name: .uploadStarted,
            object: nil,
            userInfo: ["didCompress": didCompressActiveUpload]
        )
    }

    private func observeProgress(from service: ImageHostingService) -> AnyCancellable {
        uploadProgress = .zero
        return service.$uploadProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.uploadProgress = progress
                NotificationCenter.default.post(
                    name: .uploadProgressUpdated,
                    object: nil,
                    userInfo: ["progress": progress.fractionCompleted]
                )
            }
    }

    private func handleUploadFailure(_ error: Error) {
        statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
        notificationManager.sendErrorNotification(message: statusMessage)
    }

    private func handleCompressionFailure(_ error: Error) {
        isCompressing = false
        didCompressActiveUpload = false
        compressionProgress = .zero
        statusMessage = L10n.tr("status.compressionFailed", error.localizedDescription)
        notificationManager.sendErrorNotification(message: statusMessage)
    }

    private func handleLivePhotoConversionFailure(_ error: Error) {
        isCompressing = false
        didCompressActiveUpload = false
        compressionProgress = .zero
        statusMessage = L10n.tr("status.livePhotoConversionFailed", error.localizedDescription)
        notificationManager.sendErrorNotification(message: statusMessage)
    }

    func saveSettings(_ settings: AppSettings) {
        var updated = normalized(settings)
        // The menu owns this preference; saving an already-open Settings window
        // must not overwrite a more recent menu selection.
        updated.copyLinksAsMarkdown = appSettings.copyLinksAsMarkdown
        appSettings = updated
        persistSettings()
    }

    func setCopyLinksAsMarkdown(_ isEnabled: Bool) {
        guard appSettings.copyLinksAsMarkdown != isEnabled else { return }
        appSettings.copyLinksAsMarkdown = isEnabled
        persistSettings()
        recopyLatestUploadedLink()
    }

    /// 切换链接格式后，用新格式把最近一次上传的链接重新复制到剪切板
    func recopyLatestUploadedLink() {
        guard let latest = uploadedImages.first else { return }
        let asMarkdown = appSettings.copyLinksAsMarkdown
        guard linkClipboard.copy(latest, asMarkdown: asMarkdown, playSound: true) else { return }
        let link = ImageLinkFormatter.string(for: latest, asMarkdown: asMarkdown)
        statusMessage = L10n.tr("status.linkCopied", link)
        notificationManager.sendLinkCopiedNotification(link: link)
    }

    func setCaptionBeforeUploadEnabled(_ isEnabled: Bool) {
        appSettings.captionBeforeUpload = isEnabled
        persistSettings()
    }

    func setUploadCompressionEnabled(_ isEnabled: Bool) {
        appSettings.uploadCompression.isEnabled = isEnabled
        persistSettings()
    }

    func setLivePhotoGIFConversionEnabled(_ isEnabled: Bool) {
        appSettings.uploadCompression.convertClipboardLivePhotosToGIF = isEnabled
        persistSettings()
    }

    func addProfile(provider: ImageHostProvider) {
        appSettings.profiles.append(ImageHostProfile.blank(provider: provider))
        appSettings.activeProfileID = appSettings.profiles.last?.id
        persistSettings()
    }

    func deleteProfile(id: UUID) {
        appSettings.profiles.removeAll { $0.id == id }
        appSettings = normalized(appSettings)
        persistSettings()
    }

    func selectProfile(id: UUID) {
        appSettings.activeProfileID = id
        persistSettings()
    }

    func updateProfile(_ profile: ImageHostProfile) {
        guard let index = appSettings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        appSettings.profiles[index] = profile
        persistSettings()
    }

    func validateProfile(_ profile: ImageHostProfile) async throws -> Bool {
        let service = ImageHostingService(config: profile)
        return try await service.validateConfig()
    }

    private func persistSettings() {
        appSettings = normalized(appSettings)
        do {
            try storageService.saveAppSettings(appSettings)
        } catch {
            statusMessage = L10n.tr("status.settingsSaveFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }
        syncLaunchAtLoginIfNeeded()
        NotificationCenter.default.post(name: .settingsUpdated, object: nil)
    }

    private func normalized(_ settings: AppSettings) -> AppSettings {
        var settings = settings
        if settings.profiles.isEmpty {
            settings.profiles = AppSettings.default.profiles
        }
        if settings.activeProfileID == nil || !settings.profiles.contains(where: { $0.id == settings.activeProfileID }) {
            settings.activeProfileID = settings.profiles.first?.id
        }
        return settings
    }

    private func confirmLargeFileUpload(file: UploadableFile) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.tr("largeFile.title")
        alert.informativeText = L10n.tr(
            "largeFile.message",
            file.fileName,
            ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("largeFile.continue"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func syncLaunchAtLoginIfNeeded() {
        do {
            try launchAtLoginService.sync(isEnabled: appSettings.launchAtLogin)
        } catch {
            let fallback = normalized(appSettings)
            if fallback.launchAtLogin {
                appSettings.launchAtLogin = false
                try? storageService.saveAppSettings(appSettings)
            }
            statusMessage = L10n.tr("status.launchAtLoginFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
        }
    }

    private func currentClipboardImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return image
        }

        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData) {
            return image
        }

        return nil
    }

    func copyImageURL(_ image: UploadedImage) {
        guard linkClipboard.copy(image, asMarkdown: appSettings.copyLinksAsMarkdown, playSound: true) else { return }
        statusMessage = L10n.tr("status.linkCopied", image.url)
    }

    func deleteImage(id: UUID) {
        uploadedImages.removeAll { $0.id == id }
        storageService.deleteUploadedImage(id: id)
    }

    func clearAllImages() {
        uploadedImages.removeAll()
        storageService.clearUploadedImages()
    }

    var displayedImages: [UploadedImage] {
        Array(uploadedImages.prefix(maxDisplayedImages))
    }

    var hasMoreImages: Bool {
        uploadedImages.count > maxDisplayedImages
    }

    var allImages: [UploadedImage] {
        uploadedImages
    }

    func clearTransientStatus() {
        statusMessage = ""
    }
}
