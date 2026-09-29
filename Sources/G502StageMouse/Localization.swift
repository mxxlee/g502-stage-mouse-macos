import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case french = "fr"

    var titleKey: String {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .french: return "language.french"
        }
    }
}

enum L10n {
    static let preferenceKey = "g502x.language"

    static var selectedLanguage: AppLanguage {
        let value = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        return AppLanguage(rawValue: value) ?? .system
    }

    static func select(_ language: AppLanguage) {
        _ = activeLanguage
        UserDefaults.standard.set(language.rawValue, forKey: preferenceKey)
    }

    static func string(_ key: String) -> String {
        if let selectedBundle {
            let value = selectedBundle.localizedString(forKey: key, value: key, table: nil)
            if value != key { return value }
        }
        return englishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: activeLocale, arguments: arguments)
    }

    private static let activeLanguage = selectedLanguage
    private static let selectedBundle = bundle(for: activeLanguage)
    private static let englishBundle = bundle(for: .english)

    private static let activeLocale: Locale = {
        switch activeLanguage {
        case .system: return .current
        case .english: return Locale(identifier: "en")
        case .french: return Locale(identifier: "fr")
        }
    }()

    private static func bundle(for language: AppLanguage) -> Bundle? {
        if language == .system { return .main }
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
