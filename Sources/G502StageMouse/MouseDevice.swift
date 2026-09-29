import Foundation

enum MouseDevice: String, CaseIterable {
    case powerplayReceiver = "C53A"
    case lightspeedReceiver = "C547"
    case lightspeedWired = "C098"
    case g502xWired = "C099"

    var pid: String { rawValue }

    var productID: Int { Int(rawValue, radix: 16) ?? 0 }

    var hasBattery: Bool { self != .g502xWired }

    var supportsLegacyProfileRestore: Bool { self != .g502xWired }

    var supportsPersistentDPI: Bool { self != .g502xWired }

    func calibrationKey(button: Int) -> String {
        let prefix = self == .g502xWired ? "g502x.wired" : "g502x"
        return "\(prefix).physicalIndex.g\(button)"
    }

    static let defaultPhysicalIndexToG: [Int: Int] = [
        2: 3,
        3: 4,
        5: 5,
        4: 6,
        10: 7,
        9: 8,
        8: 9
    ]

    func physicalIndexMap(buttons: [Int], store: UserDefaults = .standard) -> [Int: Int] {
        var map = Self.defaultPhysicalIndexToG
        for button in buttons {
            let key = calibrationKey(button: button)
            guard store.object(forKey: key) != nil else { continue }
            Self.assign(index: store.integer(forKey: key), button: button, in: &map)
        }
        return map
    }

    func saveCalibration(index: Int, button: Int, store: UserDefaults = .standard) {
        store.set(index, forKey: calibrationKey(button: button))
    }

    static func assign(index: Int, button: Int, in map: inout [Int: Int]) {
        let stale = map.compactMap { entry in
            entry.key == index || entry.value == button ? entry.key : nil
        }
        stale.forEach { map.removeValue(forKey: $0) }
        map[index] = button
    }

    static func select(from entries: [[String: Any]]) -> (device: MouseDevice, path: String)? {
        for device in allCases {
            if let entry = entries.first(where: { ($0["pid"] as? String) == device.pid }),
               let path = entry["path"] as? String {
                return (device, path)
            }
        }
        return nil
    }
}
