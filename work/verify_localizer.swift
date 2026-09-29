import Foundation

@main
enum VerifyLocalizer {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected english, french, fallback, missingKey, system, or earlySelect")
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
            let retryDelay = L10n.formattedNumber(0.5, fractionDigits: 1)
            precondition(retryDelay == "0.5")
            precondition(L10n.formattedNumber(1, fractionDigits: 1) == "1.0")
            precondition(
                L10n.format("status.reconnectIn", retryDelay) == "Reconnecting automatically in 0.5 s"
            )
            precondition(L10n.string("missing.key") == "missing.key")
            L10n.select(.french)
            precondition(defaults.string(forKey: L10n.preferenceKey) == "fr")
            precondition(L10n.selectedLanguage == .french)
            precondition(L10n.string("action.historyBack") == "Back")
        case "french":
            defaults.set(AppLanguage.french.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.string("action.historyBack") == "Retour arrière")
            precondition(L10n.format("battery.level.exact", 42) == "42 %")
            let retryDelay = L10n.formattedNumber(0.5, fractionDigits: 1)
            precondition(retryDelay == "0,5")
            precondition(L10n.formattedNumber(1, fractionDigits: 0) == "1")
            precondition(L10n.formattedNumber(1, fractionDigits: 1) == "1,0")
            precondition(
                L10n.format("status.reconnectIn", retryDelay) == "Reconnexion automatique dans 0,5 s"
            )
            precondition(
                L10n.format("diagnostic.retry.deviceReturned", retryDelay, 1, 6)
                    == "Nouvelle tentative dans 0,5 s (retour du périphérique, palier 1/6)."
            )
        case "fallback":
            defaults.set(AppLanguage.french.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.string("action.historyBack") == "Back")
            precondition(L10n.format("battery.level.exact", 42) == "42%")
        case "missingKey":
            defaults.set(AppLanguage.french.rawValue, forKey: L10n.preferenceKey)
            let frenchPath = Bundle.main.path(
                forResource: "Localizable", ofType: "strings", inDirectory: "fr.lproj"
            )!
            let data = try! Data(contentsOf: URL(fileURLWithPath: frenchPath))
            var translations = try! PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as! [String: String]
            precondition(translations.removeValue(forKey: "action.historyBack") == "Retour arrière")
            let missingKeyTable = try! PropertyListSerialization.data(
                fromPropertyList: translations, format: .binary, options: 0
            )
            try! missingKeyTable.write(to: URL(fileURLWithPath: frenchPath))
            precondition(L10n.string("action.historyBack") == "Back")
            precondition(L10n.string("action.historyForward") == "Retour avant")
        case "system":
            defaults.removeObject(forKey: L10n.preferenceKey)
            let mainValue = Bundle.main.localizedString(
                forKey: "action.historyBack", value: "action.historyBack", table: nil
            )
            let expected = mainValue == "action.historyBack" ? "Back" : mainValue
            precondition(L10n.string("action.historyBack") == expected)
        case "earlySelect":
            defaults.set(AppLanguage.english.rawValue, forKey: L10n.preferenceKey)
            precondition(L10n.selectedLanguage == .english)
            L10n.select(.french)
            precondition(L10n.selectedLanguage == .french)
            precondition(L10n.string("action.historyBack") == "Back", "Language changed before relaunch")
            precondition(L10n.format("battery.level.exact", 42) == "42%")
        default:
            fatalError("Unknown test case")
        }

        defaults.removeObject(forKey: L10n.preferenceKey)
        print("localizer \(CommandLine.arguments[1]): pass")
    }
}
