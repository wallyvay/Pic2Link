import Foundation
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// 已上传图片的数据模型
struct UploadedImage: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let url: String
    let uploadDate: Date
    let thumbnailData: Data?
    let caption: String?

    init(id: UUID = UUID(), fileName: String, url: String, uploadDate: Date = Date(), thumbnailData: Data? = nil, caption: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.uploadDate = uploadDate
        self.thumbnailData = thumbnailData
        self.caption = caption.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    var fileExtension: String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    var contentType: UTType? {
        let ext = (fileName as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    var isImageFile: Bool {
        if thumbnailData != nil {
            return true
        }
        return contentType?.conforms(to: .image) ?? false
    }

    /// 从 NSImage 创建缩略图数据
    static func createThumbnail(from image: NSImage, maxSize: CGFloat = 240) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.size.width
        let height = bitmap.size.height
        let ratio = min(maxSize / width, maxSize / height)
        let newWidth = width * ratio
        let newHeight = height * ratio

        let newRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newWidth),
            pixelsHigh: Int(newHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = newRep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        image.draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: NSRect.zero,
            operation: .copy,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

enum PathStyle: String, Codable, CaseIterable, Identifiable {
    case dateFolder = "按日期文件夹"
    case flat = "平铺模式"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateFolder: return L10n.tr("pathStyle.dateFolder")
        case .flat: return L10n.tr("pathStyle.flat")
        }
    }
}

enum ImageHostProvider: String, Codable, CaseIterable, Identifiable {
    case alibabaOSS
    case synologyC2
    case jdCloud
    case baiduBOS
    case tencentCOS
    case qiniu
    case upyun
    case amazonS3
    case googleCloudStorage
    case cloudflareR2
    case backblazeB2
    case genericS3Compatible
    case webDAV
    case flickr
    case imgur

    var id: String { rawValue }

    var displayName: String {
        L10n.tr("provider.\(rawValue)")
    }

    var defaultProfileName: String {
        displayName
    }

    var legacyAutomaticNames: Set<String> {
        switch self {
        case .alibabaOSS: return ["阿里云 OSS", "默认 阿里云 OSS"]
        case .synologyC2: return ["Synology C2", "Synology C2 Object Storage"]
        case .jdCloud: return ["京东云对象存储"]
        case .baiduBOS: return ["百度云 BOS"]
        case .tencentCOS: return ["腾讯云 COS"]
        case .qiniu: return ["七牛"]
        case .upyun: return ["又拍", "又拍云"]
        case .amazonS3: return ["Amazon S3"]
        case .googleCloudStorage: return ["Google Cloud Storage"]
        case .cloudflareR2: return ["Cloudflare R2"]
        case .backblazeB2: return ["Backblaze B2"]
        case .genericS3Compatible: return ["S3 Compatible"]
        case .webDAV: return ["WebDAV"]
        case .flickr: return ["Flickr"]
        case .imgur: return ["Imgur"]
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .alibabaOSS:
            return "oss-cn-hangzhou.aliyuncs.com"
        case .synologyC2:
            return "<region>.c2.storage.synology.com"
        case .jdCloud:
            return "s3.cn-north-1.jdcloud-oss.com"
        case .baiduBOS:
            return "s3.bj.bcebos.com"
        case .tencentCOS:
            return "cos.ap-shanghai.myqcloud.com"
        case .qiniu:
            return "upload.qiniup.com"
        case .upyun:
            return "v0.api.upyun.com"
        case .amazonS3:
            return "s3.us-east-1.amazonaws.com"
        case .googleCloudStorage:
            return "storage.googleapis.com"
        case .cloudflareR2:
            return "<account-id>.r2.cloudflarestorage.com"
        case .backblazeB2:
            return "s3.us-west-004.backblazeb2.com"
        case .genericS3Compatible:
            return "s3-compatible.example.com"
        case .webDAV:
            return "https://dav.example.com/remote.php/dav/files/username"
        case .flickr:
            return "up.flickr.com/services/upload/"
        case .imgur:
            return "api.imgur.com/3/image"
        }
    }

    var supportsPathStyle: Bool {
        switch self {
        case .alibabaOSS, .synologyC2, .jdCloud, .baiduBOS, .qiniu, .upyun, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible, .tencentCOS, .webDAV:
            return true
        case .flickr, .imgur:
            return false
        }
    }

    var usesS3Signature: Bool {
        switch self {
        case .synologyC2, .jdCloud, .baiduBOS, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible, .tencentCOS:
            return true
        default:
            return false
        }
    }

    var requiresPublicURL: Bool {
        switch self {
        case .flickr, .imgur:
            return false
        default:
            return true
        }
    }

    var containerFieldTitle: String {
        switch self {
        case .webDAV:
            return L10n.tr("field.remoteDirectory")
        case .upyun:
            return L10n.tr("field.serviceName")
        default:
            return L10n.tr("field.bucket")
        }
    }

    var containerFieldPlaceholder: String {
        switch self {
        case .webDAV:
            return L10n.tr("field.remoteDirectory.placeholder")
        case .upyun:
            return L10n.tr("field.serviceName.placeholder")
        default:
            return L10n.tr("field.bucket.placeholder")
        }
    }

    var helpText: String {
        L10n.tr("provider.help.\(rawValue)")
    }

    var supportsArbitraryFiles: Bool {
        switch self {
        case .alibabaOSS, .synologyC2, .jdCloud, .baiduBOS, .tencentCOS, .qiniu, .upyun, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible, .webDAV:
            return true
        case .flickr, .imgur:
            return false
        }
    }

    var supportedFileSummary: String {
        L10n.tr(supportsArbitraryFiles ? "fileSupport.all" : "fileSupport.imagesOnly")
    }
}

struct UploadableFile {
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let contentType: UTType?
    let mimeType: String
    let isImage: Bool

    init(fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .nameKey, .contentTypeKey])
        if values.isDirectory == true {
            throw UploadServiceError.directoryUploadUnsupported
        }

        self.fileURL = fileURL
        self.fileName = values.name ?? fileURL.lastPathComponent
        self.fileSize = Int64(values.fileSize ?? 0)
        self.contentType = values.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        self.isImage = contentType?.conforms(to: .image) ?? false
        self.mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
    }
}

enum ShortcutKey: String, Codable, CaseIterable, Identifiable {
    case a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G", h = "H", i = "I", j = "J", k = "K", l = "L", m = "M"
    case n = "N", o = "O", p = "P", q = "Q", r = "R", s = "S", t = "T", u = "U", v = "V", w = "W", x = "X", y = "Y", z = "Z"

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .a: return UInt32(kVK_ANSI_A)
        case .b: return UInt32(kVK_ANSI_B)
        case .c: return UInt32(kVK_ANSI_C)
        case .d: return UInt32(kVK_ANSI_D)
        case .e: return UInt32(kVK_ANSI_E)
        case .f: return UInt32(kVK_ANSI_F)
        case .g: return UInt32(kVK_ANSI_G)
        case .h: return UInt32(kVK_ANSI_H)
        case .i: return UInt32(kVK_ANSI_I)
        case .j: return UInt32(kVK_ANSI_J)
        case .k: return UInt32(kVK_ANSI_K)
        case .l: return UInt32(kVK_ANSI_L)
        case .m: return UInt32(kVK_ANSI_M)
        case .n: return UInt32(kVK_ANSI_N)
        case .o: return UInt32(kVK_ANSI_O)
        case .p: return UInt32(kVK_ANSI_P)
        case .q: return UInt32(kVK_ANSI_Q)
        case .r: return UInt32(kVK_ANSI_R)
        case .s: return UInt32(kVK_ANSI_S)
        case .t: return UInt32(kVK_ANSI_T)
        case .u: return UInt32(kVK_ANSI_U)
        case .v: return UInt32(kVK_ANSI_V)
        case .w: return UInt32(kVK_ANSI_W)
        case .x: return UInt32(kVK_ANSI_X)
        case .y: return UInt32(kVK_ANSI_Y)
        case .z: return UInt32(kVK_ANSI_Z)
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    var key: ShortcutKey
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let `default` = KeyboardShortcut(key: .u, command: true, option: false, control: false, shift: false)
    static let selectedPhotos = KeyboardShortcut(key: .u, command: true, option: false, control: false, shift: true)

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if command { flags |= UInt32(cmdKey) }
        if option { flags |= UInt32(optionKey) }
        if control { flags |= UInt32(controlKey) }
        if shift { flags |= UInt32(shiftKey) }
        return flags
    }

    var displayString: String {
        var pieces: [String] = []
        if control { pieces.append("^") }
        if option { pieces.append("⌥") }
        if shift { pieces.append("⇧") }
        if command { pieces.append("⌘") }
        pieces.append(key.rawValue)
        return pieces.joined()
    }
}

enum UploadResizeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case width
    case height
    case percentage
    case free
    case maximum

    var id: Self { self }

    var displayName: String {
        L10n.tr("compression.mode.\(rawValue)")
    }
}

struct UploadCompressionSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: UploadResizeMode
    var width: Int
    var height: Int
    var percentage: Double
    /// 仅对剪贴板中可确认拥有配对视频的实况照片生效。
    /// 普通静态图片始终沿用原有上传路径，不会被转换成 GIF。
    var convertClipboardLivePhotosToGIF: Bool

    init(
        isEnabled: Bool,
        mode: UploadResizeMode,
        width: Int,
        height: Int,
        percentage: Double,
        convertClipboardLivePhotosToGIF: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.width = width
        self.height = height
        self.percentage = percentage
        self.convertClipboardLivePhotosToGIF = convertClipboardLivePhotosToGIF
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case mode
        case width
        case height
        case percentage
        case convertClipboardLivePhotosToGIF
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        mode = try container.decode(UploadResizeMode.self, forKey: .mode)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        percentage = try container.decode(Double.self, forKey: .percentage)
        convertClipboardLivePhotosToGIF = try container.decodeIfPresent(
            Bool.self,
            forKey: .convertClipboardLivePhotosToGIF
        ) ?? false
    }

    static let `default` = UploadCompressionSettings(
        isEnabled: false,
        mode: .maximum,
        width: 1_920,
        height: 1_080,
        percentage: 50
    )
}

struct ImageHostProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var provider: ImageHostProvider
    var bucketName: String
    var accessKey: String
    var secretKey: String
    var publicURL: String
    var endpoint: String
    var region: String
    var pathStyle: PathStyle
    var basePath: String
    var operatorName: String
    var password: String
    var apiKey: String
    var sharedSecret: String
    var authToken: String
    var authTokenSecret: String
    var clientID: String

    init(
        id: UUID = UUID(),
        name: String = ImageHostProvider.alibabaOSS.defaultProfileName,
        provider: ImageHostProvider = .alibabaOSS,
        bucketName: String = "",
        accessKey: String = "",
        secretKey: String = "",
        publicURL: String = "",
        endpoint: String = ImageHostProvider.alibabaOSS.defaultEndpoint,
        region: String = "",
        pathStyle: PathStyle = .dateFolder,
        basePath: String = "",
        operatorName: String = "",
        password: String = "",
        apiKey: String = "",
        sharedSecret: String = "",
        authToken: String = "",
        authTokenSecret: String = "",
        clientID: String = ""
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.bucketName = bucketName
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.publicURL = publicURL
        self.endpoint = endpoint
        self.region = region
        self.pathStyle = pathStyle
        self.basePath = basePath
        self.operatorName = operatorName
        self.password = password
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.authToken = authToken
        self.authTokenSecret = authTokenSecret
        self.clientID = clientID
    }

    static let sample = ImageHostProfile()

    static func blank(provider: ImageHostProvider) -> ImageHostProfile {
        ImageHostProfile(
            name: "",
            provider: provider,
            endpoint: provider.defaultEndpoint,
            region: provider == .cloudflareR2 ? "auto" : (provider == .googleCloudStorage ? "auto" : "")
        )
    }

    var displayName: String {
        name.isEmpty ? provider.defaultProfileName : name
    }

    var providerSummary: String {
        switch provider {
        case .alibabaOSS, .synologyC2, .jdCloud, .baiduBOS, .tencentCOS, .qiniu, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible, .webDAV:
            return bucketName.isEmpty ? provider.displayName : "\(provider.displayName) · \(bucketName)"
        case .upyun:
            return bucketName.isEmpty ? provider.displayName : "\(provider.displayName) · \(bucketName)"
        case .flickr:
            return provider.displayName
        case .imgur:
            return provider.displayName
        }
    }

    var resolvedBasePath: String {
        basePath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var isConfigured: Bool {
        switch provider {
        case .alibabaOSS:
            return !bucketName.isEmpty && !accessKey.isEmpty && !secretKey.isEmpty && !publicURL.isEmpty && !endpoint.isEmpty
        case .synologyC2, .jdCloud, .baiduBOS, .tencentCOS, .amazonS3, .googleCloudStorage, .cloudflareR2, .backblazeB2, .genericS3Compatible:
            return !bucketName.isEmpty && !accessKey.isEmpty && !secretKey.isEmpty && !endpoint.isEmpty && !publicURL.isEmpty
        case .qiniu:
            return !bucketName.isEmpty && !accessKey.isEmpty && !secretKey.isEmpty && !endpoint.isEmpty && !publicURL.isEmpty
        case .upyun:
            return !bucketName.isEmpty && !operatorName.isEmpty && !password.isEmpty && !publicURL.isEmpty
        case .webDAV:
            return !accessKey.isEmpty && !secretKey.isEmpty && !endpoint.isEmpty && !publicURL.isEmpty
        case .flickr:
            return !apiKey.isEmpty && !sharedSecret.isEmpty && !authToken.isEmpty
        case .imgur:
            return !clientID.isEmpty
        }
    }
}

struct AppSettings: Codable, Equatable {
    var profiles: [ImageHostProfile]
    var activeProfileID: UUID?
    var uploadShortcut: KeyboardShortcut
    var launchAtLogin: Bool
    var uploadCompression: UploadCompressionSettings
    var captionBeforeUpload = false
    var copyLinksAsMarkdown = false

    static let `default` = AppSettings(
        profiles: [ImageHostProfile.blank(provider: .alibabaOSS)],
        activeProfileID: nil,
        uploadShortcut: .default,
        launchAtLogin: false,
        uploadCompression: .default
    )

    enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileID
        case uploadShortcut
        case launchAtLogin
        case uploadCompression
        case captionBeforeUpload
        case copyLinksAsMarkdown
    }

    init(
        profiles: [ImageHostProfile],
        activeProfileID: UUID?,
        uploadShortcut: KeyboardShortcut,
        launchAtLogin: Bool,
        uploadCompression: UploadCompressionSettings = .default,
        captionBeforeUpload: Bool = false,
        copyLinksAsMarkdown: Bool = false
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.uploadShortcut = uploadShortcut
        self.launchAtLogin = launchAtLogin
        self.uploadCompression = uploadCompression
        self.captionBeforeUpload = captionBeforeUpload
        self.copyLinksAsMarkdown = copyLinksAsMarkdown
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([ImageHostProfile].self, forKey: .profiles)
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        uploadShortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .uploadShortcut) ?? .default
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        uploadCompression = try container.decodeIfPresent(UploadCompressionSettings.self, forKey: .uploadCompression) ?? .default
        captionBeforeUpload = try container.decodeIfPresent(Bool.self, forKey: .captionBeforeUpload) ?? false
        copyLinksAsMarkdown = try container.decodeIfPresent(Bool.self, forKey: .copyLinksAsMarkdown) ?? false
    }

    var activeProfile: ImageHostProfile? {
        if let activeProfileID,
           let match = profiles.first(where: { $0.id == activeProfileID }) {
            return match
        }

        return profiles.first
    }
}

/// 兼容旧版单 OSS 配置，便于迁移历史用户数据
struct OSSConfig: Codable {
    var bucketName: String
    var accessKey: String
    var secretKey: String
    var urlPrefix: String
    var endpoint: String
    var pathStyle: PathStyle

    init(
        bucketName: String = "",
        accessKey: String = "",
        secretKey: String = "",
        urlPrefix: String = "",
        endpoint: String = ImageHostProvider.alibabaOSS.defaultEndpoint,
        pathStyle: PathStyle = .dateFolder
    ) {
        self.bucketName = bucketName
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.urlPrefix = urlPrefix
        self.endpoint = endpoint
        self.pathStyle = pathStyle
    }
}
