import AppKit

enum Action: String, CaseIterable {
    case none

    var title: String { L10n.string("action.none") }
}

enum L10n {
    static let french: [String: String] = {
        guard CommandLine.arguments.count == 2,
              let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            fatalError("Expected French Localizable.strings path")
        }
        return table
    }()

    static func string(_ key: String) -> String {
        guard let value = french[key] else { fatalError("Missing French key: \(key)") }
        return value
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale(identifier: "fr"), arguments: arguments)
    }
}

@main
enum VerifyVisualDPILayout {
    private static func find<T: NSView>(_ type: T.Type, in view: NSView, matching: (T) -> Bool) -> T? {
        if let candidate = view as? T, matching(candidate) { return candidate }
        for child in view.subviews {
            if let found = find(type, in: child, matching: matching) { return found }
        }
        return nil
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }

    static func main() {
        _ = NSApplication.shared
        let controller = VisualConfigWindowController(
            getMappings: { [:] },
            setMapping: { _, _ in },
            startCalibration: { _ in },
            readDPI: { _ in },
            setDPI: { _, _, _ in }
        )
        guard let content = controller.window?.contentView else { fail("Visual window has no content") }
        content.layoutSubtreeIfNeeded()

        guard let apply = find(NSButton.self, in: content, matching: { $0.title == L10n.string("dpi.apply") }) else {
            fail("French Apply button is missing")
        }
        var ancestor = apply.superview
        while ancestor != nil && !(ancestor is NSVisualEffectView) { ancestor = ancestor?.superview }
        guard let card = ancestor else { fail("DPI card is missing") }
        card.layoutSubtreeIfNeeded()

        guard let preset = find(NSPopUpButton.self, in: card, matching: { $0.title == L10n.string("dpi.preset") }),
              let persist = find(NSButton.self, in: card, matching: { $0.title == L10n.string("dpi.persist") }) else {
            fail("French DPI controls are missing")
        }

        let inner = card.bounds.insetBy(dx: 12, dy: 0)
        guard abs(inner.width - 296) <= 1 else {
            fail("DPI card content width changed at normal window size: \(inner.width) pt")
        }
        for (name, control) in [("preset", preset as NSView), ("persist", persist), ("apply", apply)] {
            let frame = control.convert(control.bounds, to: card)
            guard frame.minX >= inner.minX - 1, frame.maxX <= inner.maxX + 1 else {
                fail("French DPI \(name) overflows card: frame \(frame), available \(inner)")
            }
            guard frame.minY >= 9 - 1, frame.maxY <= card.bounds.maxY - 9 + 1 else {
                fail("French DPI \(name) overflows card height: frame \(frame), card \(card.bounds)")
            }
            guard frame.width + 1 >= control.intrinsicContentSize.width else {
                fail("French DPI \(name) is compressed: frame \(frame), intrinsic \(control.intrinsicContentSize)")
            }
        }
        print("French DPI controls fit inside \(Int(inner.width)) pt card content width")
    }
}
