import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// 主视图模型
@MainActor
class MainViewModel: ObservableObject {
    static let shared = MainViewModel()
    private let largeFileThreshold: Int64 = 200 * 1024 * 1024

    private let storageService = StorageService.shared
    private let notificationManager = NotificationManager.shared
    private let launchAtLoginService = LaunchAtLoginService.shared
    private var hostingService: ImageHostingService?

    @Published var appSettings: AppSettings
    @Published var uploadedImages: [UploadedImage] = []
    @Published var isUploading = false
    @Published var uploadProgress = UploadProgress.zero
    @Published var statusMessage: String = ""

    let maxDisplayedImages = 10

    init() {
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

    /// 上传指定图片
    func uploadImage(_ image: NSImage) async {
        guard !isUploading else {
            statusMessage = L10n.tr("status.uploadBusy")
            return
        }

        guard let profile = activeProfile else {
            statusMessage = L10n.tr("status.configureFirst")
            return
        }

        guard profile.isConfigured else {
            statusMessage = L10n.tr("status.incompleteConfig")
            return
        }

        hostingService = ImageHostingService(config: profile)
        guard let service = hostingService else { return }

        isUploading = true
        uploadProgress = .zero
        statusMessage = L10n.tr("status.uploadingTo", profile.displayName)
        NotificationCenter.default.post(name: .uploadStarted, object: nil)

        let progressCancellable = service.$uploadProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.uploadProgress = progress
                NotificationCenter.default.post(
                    name: .uploadProgressUpdated,
                    object: nil,
                    userInfo: ["progress": progress.fractionCompleted]
                )
            }

        do {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
                throw UploadServiceError.invalidConfig
            }

            let thumbnailData = UploadedImage.createThumbnail(from: image)
            let url = try await service.uploadImage(pngData)

            let fileName = url.components(separatedBy: "/").last ?? "image.png"
            let uploadedImage = UploadedImage(
                fileName: fileName,
                url: url,
                thumbnailData: thumbnailData
            )

            uploadedImages.insert(uploadedImage, at: 0)
            storageService.addUploadedImage(uploadedImage)

            copyToClipboard(url)
            notificationManager.sendUploadCompleteNotification(fileName: fileName, imageURL: url)
            statusMessage = L10n.tr("status.uploadSuccess", profile.displayName)
        } catch {
            statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
        }

        progressCancellable.cancel()
        isUploading = false
        uploadProgress = .zero
        NotificationCenter.default.post(name: .uploadFinished, object: nil)
    }

    func uploadClipboardImage() async {
        guard let image = currentClipboardImage() else {
            statusMessage = L10n.tr("status.clipboardEmpty")
            notificationManager.sendErrorNotification(message: statusMessage)
            return
        }

        await uploadImage(image)
    }

    func uploadFile(at fileURL: URL) async {
        guard !isUploading else {
            statusMessage = L10n.tr("status.uploadBusy")
            return
        }

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

            hostingService = ImageHostingService(config: profile)
            guard let service = hostingService else { return }

            isUploading = true
            uploadProgress = .zero
            statusMessage = L10n.tr("status.uploadingFile", uploadableFile.fileName)
            NotificationCenter.default.post(name: .uploadStarted, object: nil)

            let progressCancellable = service.$uploadProgress
                .receive(on: RunLoop.main)
                .sink { [weak self] progress in
                    self?.uploadProgress = progress
                    NotificationCenter.default.post(
                        name: .uploadProgressUpdated,
                        object: nil,
                        userInfo: ["progress": progress.fractionCompleted]
                    )
                }

            defer {
                progressCancellable.cancel()
                isUploading = false
                uploadProgress = .zero
                NotificationCenter.default.post(name: .uploadFinished, object: nil)
            }

            let fileData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let uploadedURL = try await service.uploadFile(
                fileData,
                fileName: uploadableFile.fileName,
                mimeType: uploadableFile.mimeType
            )

            let thumbnailData: Data?
            if uploadableFile.isImage, let image = NSImage(contentsOf: fileURL) {
                thumbnailData = UploadedImage.createThumbnail(from: image)
            } else {
                thumbnailData = nil
            }

            let uploadedImage = UploadedImage(
                fileName: uploadableFile.fileName,
                url: uploadedURL,
                thumbnailData: thumbnailData
            )

            uploadedImages.insert(uploadedImage, at: 0)
            storageService.addUploadedImage(uploadedImage)
            copyToClipboard(uploadedURL)
            notificationManager.sendUploadCompleteNotification(fileName: uploadableFile.fileName, imageURL: uploadedURL)
            statusMessage = L10n.tr("status.uploadSuccess", uploadableFile.fileName)
        } catch {
            statusMessage = L10n.tr("status.uploadFailed", error.localizedDescription)
            notificationManager.sendErrorNotification(message: statusMessage)
        }
    }

    func saveSettings(_ settings: AppSettings) {
        appSettings = normalized(settings)
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
        if let activeProfile {
            hostingService?.updateConfig(activeProfile)
        }
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

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let fileURLString = item.string(forType: .fileURL),
                   let decoded = fileURLString.removingPercentEncoding,
                   let url = URL(string: decoded),
                   url.isFileURL,
                   let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }

        return nil
    }

    func copyImageURL(_ image: UploadedImage) {
        copyToClipboard(image.url)
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
