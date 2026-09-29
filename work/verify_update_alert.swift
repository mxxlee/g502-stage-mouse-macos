import Foundation

@main
enum VerifyUpdateAlert {
    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected main.swift path")
        }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        guard source.contains("let notes: String?") else { fail("Manifest notes field is missing") }
        guard let start = source.range(of: "private func offerUpdate("),
              let end = source.range(
                of: "private func runExecutable(",
                range: start.upperBound..<source.endIndex
              ) else {
            fatalError("Could not find update alert body")
        }
        let body = source[start.upperBound..<end.lowerBound]
        guard !body.contains("manifest.notes") else { fail("Manifest notes bypass localization") }
        guard body.contains("alert.informativeText = L10n.string(\"update.available.message\")") else {
            fail("Update alert does not show the localized message")
        }
        print("update alert: localized generic message ignores manifest notes")
    }
}
