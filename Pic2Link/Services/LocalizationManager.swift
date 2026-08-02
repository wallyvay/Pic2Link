import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"
    case japanese = "ja"
    case russian = "ru"
    case spanish = "es"
    case portuguese = "pt"
    case thai = "th"
    case hindi = "hi"
    case french = "fr"
    case arabic = "ar"
    case german = "de"

    var id: String { rawValue }

    nonisolated var locale: Locale {
        Locale(identifier: rawValue)
    }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    var displayName: String {
        L10n.tr("language.name.\(rawValue)")
    }

    nonisolated static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let preferredLanguage = preferredLanguages.first else {
            return .english
        }

        let normalized = preferredLanguage.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: normalized)
        guard let languageCode = locale.language.languageCode?.identifier.lowercased() else {
            return .english
        }

        if languageCode == "zh" {
            let script = locale.language.script?.identifier.lowercased()
            let region = locale.region?.identifier.uppercased()
            if script == "hant" || ["TW", "HK", "MO"].contains(region) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        return allCases.first { $0.rawValue.lowercased() == languageCode } ?? .english
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    nonisolated private static let selectedLanguageKey = "selectedAppLanguage"
    private let defaults: UserDefaults

    @Published private(set) var currentLanguage: AppLanguage

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        currentLanguage = Self.processLanguageOverride ?? Self.resolvedLanguage(
            defaults: defaults,
            preferredLanguages: preferredLanguages
        )
    }

    var locale: Locale {
        currentLanguage.locale
    }

    var layoutDirection: LayoutDirection {
        currentLanguage.layoutDirection
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        defaults.set(language.rawValue, forKey: Self.selectedLanguageKey)
        NotificationCenter.default.post(name: .languageChanged, object: language)
    }

    nonisolated static func resolvedLanguage(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let stored = defaults.string(forKey: selectedLanguageKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }
        return AppLanguage.systemDefault(preferredLanguages: preferredLanguages)
    }

    nonisolated static func localizedString(forKey key: String, arguments: [CVarArg] = []) -> String {
        let language = processLanguageOverride ?? resolvedLanguage()
        let languageBundle = bundle(for: language) ?? bundle(for: .english) ?? .main
        let format = languageBundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    nonisolated private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    nonisolated private static var processLanguageOverride: AppLanguage? {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-openSettingsForUITesting"),
              let rawValue = ProcessInfo.processInfo.environment["PIC2LINK_UI_TEST_LANGUAGE"] else {
            return nil
        }
        return AppLanguage(rawValue: rawValue)
#else
        return nil
#endif
    }
}

enum L10n {
    nonisolated static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        LocalizationManager.localizedString(forKey: key, arguments: arguments)
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}
