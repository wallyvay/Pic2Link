import Foundation

struct ProfileCredentials: Codable, Equatable {
    var accessKey: String
    var secretKey: String
    var operatorName: String
    var password: String
    var apiKey: String
    var sharedSecret: String
    var authToken: String
    var authTokenSecret: String
    var clientID: String

    init(profile: ImageHostProfile) {
        accessKey = profile.accessKey
        secretKey = profile.secretKey
        operatorName = profile.operatorName
        password = profile.password
        apiKey = profile.apiKey
        sharedSecret = profile.sharedSecret
        authToken = profile.authToken
        authTokenSecret = profile.authTokenSecret
        clientID = profile.clientID
    }

    var isEmpty: Bool {
        accessKey.isEmpty &&
        secretKey.isEmpty &&
        operatorName.isEmpty &&
        password.isEmpty &&
        apiKey.isEmpty &&
        sharedSecret.isEmpty &&
        authToken.isEmpty &&
        authTokenSecret.isEmpty &&
        clientID.isEmpty
    }

    func apply(to profile: inout ImageHostProfile) {
        profile.accessKey = accessKey
        profile.secretKey = secretKey
        profile.operatorName = operatorName
        profile.password = password
        profile.apiKey = apiKey
        profile.sharedSecret = sharedSecret
        profile.authToken = authToken
        profile.authTokenSecret = authTokenSecret
        profile.clientID = clientID
    }
}

extension ImageHostProfile {
    mutating func removeCredentials() {
        accessKey = ""
        secretKey = ""
        operatorName = ""
        password = ""
        apiKey = ""
        sharedSecret = ""
        authToken = ""
        authTokenSecret = ""
        clientID = ""
    }
}

/// 数据持久化服务
final class StorageService {
    static let shared = StorageService()

    private let defaults: UserDefaults
    private let credentialStore: any CredentialStoring
    private let appSettingsKey = "appSettings"
    private let uploadedImagesKey = "uploadedImages"
    private let legacyOSSConfigKey = "ossConfig"

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any CredentialStoring = KeychainService.shared
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
    }

    // MARK: - 应用设置
    var appSettings: AppSettings {
        if let data = defaults.data(forKey: appSettingsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return hydrateAndMigrateCredentials(in: normalized(settings))
        }

        if let data = defaults.data(forKey: legacyOSSConfigKey),
           let legacy = try? JSONDecoder().decode(OSSConfig.self, from: data) {
            let migrated = normalized(AppSettings(
                profiles: [
                    ImageHostProfile(
                        name: "",
                        provider: .alibabaOSS,
                        bucketName: legacy.bucketName,
                        accessKey: legacy.accessKey,
                        secretKey: legacy.secretKey,
                        publicURL: legacy.urlPrefix,
                        endpoint: legacy.endpoint,
                        pathStyle: legacy.pathStyle
                    )
                ],
                activeProfileID: nil,
                uploadShortcut: .default,
                launchAtLogin: false
            ))

            if (try? saveAppSettings(migrated)) != nil {
                defaults.removeObject(forKey: legacyOSSConfigKey)
            }
            return migrated
        }

        return normalized(.default)
    }

    func saveAppSettings(_ settings: AppSettings) throws {
        let settings = normalized(settings)
        let previousProfileIDs = storedPublicSettings()?.profiles.map(\.id) ?? []
        let currentProfileIDs = Set(settings.profiles.map(\.id))
        let encoder = JSONEncoder()

        for profile in settings.profiles {
            let credentials = ProfileCredentials(profile: profile)
            let account = profile.id.uuidString
            if credentials.isEmpty {
                try credentialStore.remove(for: account)
            } else {
                try credentialStore.set(try encoder.encode(credentials), for: account)
            }
        }

        var publicSettings = settings
        for index in publicSettings.profiles.indices {
            publicSettings.profiles[index].removeCredentials()
        }
        defaults.set(try encoder.encode(publicSettings), forKey: appSettingsKey)
        defaults.removeObject(forKey: legacyOSSConfigKey)

        for removedID in previousProfileIDs where !currentProfileIDs.contains(removedID) {
            try? credentialStore.remove(for: removedID.uuidString)
        }
    }

    // MARK: - 已上传图片列表
    var uploadedImages: [UploadedImage] {
        get {
            guard let data = defaults.data(forKey: uploadedImagesKey) else {
                return []
            }
            return (try? JSONDecoder().decode([UploadedImage].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: uploadedImagesKey)
        }
    }

    /// 添加已上传图片
    func addUploadedImage(_ image: UploadedImage) {
        var images = uploadedImages
        images.insert(image, at: 0)
        uploadedImages = images
    }

    /// 删除已上传图片
    func deleteUploadedImage(id: UUID) {
        uploadedImages = uploadedImages.filter { $0.id != id }
    }

    /// 清空已上传图片
    func clearUploadedImages() {
        uploadedImages = []
    }

    private func normalized(_ settings: AppSettings) -> AppSettings {
        var settings = settings

        if settings.profiles.isEmpty {
            settings.profiles = AppSettings.default.profiles
        }

        if settings.activeProfileID == nil || !settings.profiles.contains(where: { $0.id == settings.activeProfileID }) {
            settings.activeProfileID = settings.profiles.first?.id
        }

        for index in settings.profiles.indices {
            let profile = settings.profiles[index]
            if profile.provider.legacyAutomaticNames.contains(profile.name) {
                settings.profiles[index].name = ""
            }
        }

        return settings
    }

    private func storedPublicSettings() -> AppSettings? {
        guard let data = defaults.data(forKey: appSettingsKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func hydrateAndMigrateCredentials(in settings: AppSettings) -> AppSettings {
        var hydratedSettings = settings
        var publicSettings = settings
        var didMigrate = false
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for index in settings.profiles.indices {
            let profile = settings.profiles[index]
            let account = profile.id.uuidString

            do {
                if let data = try credentialStore.data(for: account) {
                    let credentials = try decoder.decode(ProfileCredentials.self, from: data)
                    credentials.apply(to: &hydratedSettings.profiles[index])

                    if !ProfileCredentials(profile: publicSettings.profiles[index]).isEmpty {
                        publicSettings.profiles[index].removeCredentials()
                        didMigrate = true
                    }
                } else {
                    let legacyCredentials = ProfileCredentials(profile: profile)
                    guard !legacyCredentials.isEmpty else { continue }

                    try credentialStore.set(try encoder.encode(legacyCredentials), for: account)
                    publicSettings.profiles[index].removeCredentials()
                    didMigrate = true
                }
            } catch {
                // Keep legacy credentials in UserDefaults if migration cannot complete.
                continue
            }
        }

        if didMigrate, let data = try? encoder.encode(publicSettings) {
            defaults.set(data, forKey: appSettingsKey)
        }

        return hydratedSettings
    }
}
