import Foundation

@main
enum VerifyLocalizer {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected english, french, fallback, or system")
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: L10n.preferenceKey)
        precondition(L10n.selectedLanguage == .system)
        defaults.set("unsupported", forKey: L10n.preferenceKey)
        precondition(L10n.selectedLanguage == .system)

        switch CommandLine.arguments[1] {
        case "english":
            defaults.set(AppLanguage.english.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.selectedLanguage == .english)
            precondition(L10n.string("action.historyBack") == "Back")
            precondition(L10n.format("battery.level.exact", 42) == "42%")
            precondition(L10n.string("missing.key") == "missing.key")
            L10n.select(.french)
            precondition(defaults.string(forKey: L10n.preferenceKey) == "fr")
            precondition(L10n.selectedLanguage == .french)
            precondition(L10n.string("action.historyBack") == "Back")
        case "french":
            defaults.set(AppLanguage.french.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.string("action.historyBack") == "Retour arrière")
            precondition(L10n.format("battery.level.exact", 42) == "42 %")
        case "fallback":
            defaults.set(AppLanguage.french.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.string("action.historyBack") == "Back")
            precondition(L10n.format("battery.level.exact", 42) == "42%")
        case "system":
            defaults.removeObject(forKey: L10n.preferenceKey)
            let mainValue = Bundle.main.localizedString(
                forKey: "action.historyBack", value: "action.historyBack", table: nil
            )
            let expected = mainValue == "action.historyBack" ? "Back" : mainValue
            precondition(L10n.string("action.historyBack") == expected)
        default:
            fatalError("Unknown test case")
        }

        defaults.removeObject(forKey: L10n.preferenceKey)
        print("localizer \(CommandLine.arguments[1]): pass")
    }
}
