import XCTest
@testable import Pic2Link

final class LocalizationManagerTests: XCTestCase {
    func testSupportedSystemLanguagesResolveCorrectly() {
        let cases: [([String], AppLanguage)] = [
            (["en-US"], .english),
            (["zh-CN"], .simplifiedChinese),
            (["zh-Hans-SG"], .simplifiedChinese),
            (["zh-Hant-TW"], .traditionalChinese),
            (["zh-TW"], .traditionalChinese),
            (["zh-HK"], .traditionalChinese),
            (["ko-KR"], .korean),
            (["ja-JP"], .japanese),
            (["ru-RU"], .russian),
            (["es-MX"], .spanish),
            (["pt-BR"], .portuguese),
            (["th-TH"], .thai),
            (["hi-IN"], .hindi),
            (["fr-CA"], .french),
            (["ar-SA"], .arabic),
            (["de-DE"], .german)
        ]

        for (preferredLanguages, expected) in cases {
            XCTAssertEqual(
                AppLanguage.systemDefault(preferredLanguages: preferredLanguages),
                expected,
                "Failed for \(preferredLanguages)"
            )
        }
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(
            AppLanguage.systemDefault(preferredLanguages: ["it-IT"]),
            .english
        )
    }

    func testStoredLanguageOverridesSystemLanguage() {
        let suiteName = "Pic2LinkTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppLanguage.german.rawValue, forKey: "selectedAppLanguage")

        XCTAssertEqual(
            LocalizationManager.resolvedLanguage(
                defaults: defaults,
                preferredLanguages: ["ja-JP"]
            ),
            .german
        )
    }

    func testInvalidStoredLanguageUsesSystemFallback() {
        let suiteName = "Pic2LinkTests.Localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported", forKey: "selectedAppLanguage")

        XCTAssertEqual(
            LocalizationManager.resolvedLanguage(
                defaults: defaults,
                preferredLanguages: ["zh-TW"]
            ),
            .traditionalChinese
        )
    }
}
