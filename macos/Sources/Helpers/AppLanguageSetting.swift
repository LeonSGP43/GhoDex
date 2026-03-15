import Foundation

enum AppLanguageSetting: String, CaseIterable {
    case system
    case english
    case simplifiedChinese

    static let storageKey = "GhosttyAppLanguage"
    static let appleLanguagesKey = "GhosttyAppleLanguagesOverride"
    private static let bundleAppleLanguagesKey = "AppleLanguages"
    static let launchedSetting = storedSelection()

    var preferredLanguages: [String]? {
        switch self {
        case .system:
            return nil
        case .english:
            return ["en"]
        case .simplifiedChinese:
            return ["zh-Hans"]
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.Settings.languageOptionSystem
        case .english:
            return L10n.Settings.languageOptionEnglish
        case .simplifiedChinese:
            return L10n.Settings.languageOptionSimplifiedChinese
        }
    }

    static func storedSelection(
        userDefaults: UserDefaults = .standard
    ) -> Self {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              let value = Self(rawValue: rawValue) else {
            return .system
        }

        return value
    }

    static func preferredLanguages(
        userDefaults: UserDefaults = .standard,
        systemPreferredLanguages: [String] = Locale.preferredLanguages
    ) -> [String] {
        storedSelection(userDefaults: userDefaults).preferredLanguages
            ?? systemPreferredLanguages
    }

    func apply(
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(rawValue, forKey: Self.storageKey)

        switch self {
        case .system:
            userDefaults.removeObject(forKey: Self.appleLanguagesKey)
            userDefaults.removeObject(forKey: Self.bundleAppleLanguagesKey)
        case .english, .simplifiedChinese:
            userDefaults.set(preferredLanguages, forKey: Self.appleLanguagesKey)
            userDefaults.set(preferredLanguages, forKey: Self.bundleAppleLanguagesKey)
        }
    }
}
