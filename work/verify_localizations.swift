import Foundation

enum VerificationError: Error, CustomStringConvertible {
    case usage
    case invalidTable(String)
    case keyMismatch(onlyEnglish: [String], onlyFrench: [String])
    case formatMismatch(key: String, english: [String], french: [String])

    var description: String {
        switch self {
        case .usage:
            return "usage: verify_localizations.swift <English.strings> <French.strings>"
        case .invalidTable(let path):
            return "invalid strings table: \(path)"
        case .keyMismatch(let onlyEnglish, let onlyFrench):
            return "key mismatch; English only: \(onlyEnglish); French only: \(onlyFrench)"
        case .formatMismatch(let key, let english, let french):
            return "format mismatch for \(key); English: \(english); French: \(french)"
        }
    }
}

func loadTable(at path: String) throws -> [String: String] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let table = try PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: String] else {
        throw VerificationError.invalidTable(path)
    }
    return table
}

func formatConversions(in value: String) -> [String] {
    let pattern = #"%%|%(?:\d+\$)?[-+#0 ']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@diuoxXfFeEgGaAcCsSp]"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..., in: value)
    return regex.matches(in: value, range: range).compactMap {
        Range($0.range, in: value).map { String(value[$0]) }
    }.filter { $0 != "%%" }
}

do {
    guard CommandLine.arguments.count == 3 else { throw VerificationError.usage }
    let english = try loadTable(at: CommandLine.arguments[1])
    let french = try loadTable(at: CommandLine.arguments[2])
    let onlyEnglish = Array(Set(english.keys).subtracting(french.keys)).sorted()
    let onlyFrench = Array(Set(french.keys).subtracting(english.keys)).sorted()
    guard onlyEnglish.isEmpty, onlyFrench.isEmpty else {
        throw VerificationError.keyMismatch(onlyEnglish: onlyEnglish, onlyFrench: onlyFrench)
    }
    for key in english.keys.sorted() {
        let englishFormats = formatConversions(in: english[key]!)
        let frenchFormats = formatConversions(in: french[key]!)
        guard englishFormats == frenchFormats else {
            throw VerificationError.formatMismatch(
                key: key,
                english: englishFormats,
                french: frenchFormats
            )
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
