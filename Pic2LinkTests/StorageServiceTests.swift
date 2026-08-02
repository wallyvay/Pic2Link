import XCTest
@testable import Pic2Link

final class StorageServiceTests: XCTestCase {
    func testSavingSettingsMovesCredentialsOutOfUserDefaults() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let expected = makeSettings()

        try context.storage.saveAppSettings(expected)

        let storedData = try XCTUnwrap(context.defaults.data(forKey: "appSettings"))
        let publicSettings = try JSONDecoder().decode(AppSettings.self, from: storedData)
        let publicProfile = try XCTUnwrap(publicSettings.profiles.first)
        XCTAssertTrue(ProfileCredentials(profile: publicProfile).isEmpty)
        XCTAssertNotNil(context.credentials.values[publicProfile.id.uuidString])

        let hydrated = context.storage.appSettings
        XCTAssertEqual(hydrated, expected)
    }

    func testExistingPlaintextCredentialsMigrateOnRead() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let expected = makeSettings()
        context.defaults.set(try JSONEncoder().encode(expected), forKey: "appSettings")

        let hydrated = context.storage.appSettings

        XCTAssertEqual(hydrated, expected)
        let migratedData = try XCTUnwrap(context.defaults.data(forKey: "appSettings"))
        let migratedSettings = try JSONDecoder().decode(AppSettings.self, from: migratedData)
        XCTAssertTrue(ProfileCredentials(profile: try XCTUnwrap(migratedSettings.profiles.first)).isEmpty)
        XCTAssertNotNil(context.credentials.values[expected.profiles[0].id.uuidString])
    }

    func testMigrationFailureKeepsLegacyCredentials() throws {
        let context = makeContext(failWrites: true)
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let expected = makeSettings()
        context.defaults.set(try JSONEncoder().encode(expected), forKey: "appSettings")

        let hydrated = context.storage.appSettings

        XCTAssertEqual(hydrated, expected)
        let remainingData = try XCTUnwrap(context.defaults.data(forKey: "appSettings"))
        let remainingSettings = try JSONDecoder().decode(AppSettings.self, from: remainingData)
        XCTAssertFalse(ProfileCredentials(profile: try XCTUnwrap(remainingSettings.profiles.first)).isEmpty)
    }

    func testDeletingProfileRemovesItsCredentials() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        var settings = makeSettings()
        let removedProfile = ImageHostProfile(
            name: "Second",
            provider: .imgur,
            clientID: "client-id"
        )
        settings.profiles.append(removedProfile)
        try context.storage.saveAppSettings(settings)

        settings.profiles.removeAll { $0.id == removedProfile.id }
        try context.storage.saveAppSettings(settings)

        XCTAssertNil(context.credentials.values[removedProfile.id.uuidString])
        XCTAssertTrue(context.credentials.removedAccounts.contains(removedProfile.id.uuidString))
    }

    private func makeContext(failWrites: Bool = false) -> TestContext {
        let suiteName = "Pic2LinkTests.Storage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let credentials = MemoryCredentialStore(failWrites: failWrites)
        return TestContext(
            suiteName: suiteName,
            defaults: defaults,
            credentials: credentials,
            storage: StorageService(defaults: defaults, credentialStore: credentials)
        )
    }

    private func makeSettings() -> AppSettings {
        let profile = ImageHostProfile(
            name: "Private OSS",
            provider: .alibabaOSS,
            bucketName: "example-bucket",
            accessKey: "access-key",
            secretKey: "secret-key",
            publicURL: "https://example.com",
            endpoint: "oss.example.com",
            operatorName: "operator",
            password: "password",
            apiKey: "api-key",
            sharedSecret: "shared-secret",
            authToken: "auth-token",
            authTokenSecret: "auth-token-secret",
            clientID: "client-id"
        )
        return AppSettings(
            profiles: [profile],
            activeProfileID: profile.id,
            uploadShortcut: .default,
            launchAtLogin: false
        )
    }
}

private struct TestContext {
    let suiteName: String
    let defaults: UserDefaults
    let credentials: MemoryCredentialStore
    let storage: StorageService
}

private final class MemoryCredentialStore: CredentialStoring {
    enum TestError: Error {
        case writeFailed
    }

    var values: [String: Data] = [:]
    var removedAccounts: Set<String> = []
    let failWrites: Bool

    init(failWrites: Bool) {
        self.failWrites = failWrites
    }

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func set(_ data: Data, for account: String) throws {
        if failWrites { throw TestError.writeFailed }
        values[account] = data
    }

    func remove(for account: String) throws {
        values.removeValue(forKey: account)
        removedAccounts.insert(account)
    }
}
