import Foundation

@main
enum VerifyMouseDevice {
    private static func entry(_ pid: String) -> [String: Any] {
        ["pid": pid, "path": "path-\(pid)"]
    }

    static func main() {
        precondition(MouseDevice.allCases.map(\.pid) == ["C53A", "C547", "C098", "C099"])
        precondition(MouseDevice.allCases.map(\.productID) == [0xC53A, 0xC547, 0xC098, 0xC099])

        let wired = MouseDevice.select(from: [entry("C099")])
        precondition(wired?.device == .g502xWired && wired?.path == "path-C099")

        let both = MouseDevice.select(from: [entry("C099"), entry("C547")])
        precondition(both?.device == .lightspeedReceiver && both?.path == "path-C547")

        let usb = MouseDevice.select(from: [entry("C099"), entry("C098")])
        precondition(usb?.device == .lightspeedWired)

        precondition(MouseDevice.select(from: [entry("C548"), entry("DEAD")]) == nil)
        precondition(MouseDevice.select(from: []) == nil)

        precondition(MouseDevice.g502xWired.hasBattery == false)
        precondition(MouseDevice.g502xWired.supportsLegacyProfileRestore == false)
        for device in [MouseDevice.powerplayReceiver, .lightspeedReceiver, .lightspeedWired] {
            precondition(device.hasBattery && device.supportsLegacyProfileRestore)
        }

        precondition(MouseDevice.g502xWired.supportsPersistentDPI == false)
        precondition(MouseDevice.lightspeedWired.supportsPersistentDPI)
        precondition(MouseDevice.g502xWired.calibrationKey(button: 3) == "g502x.wired.physicalIndex.g3")
        precondition(MouseDevice.lightspeedReceiver.calibrationKey(button: 3) == "g502x.physicalIndex.g3")
        precondition(MouseDevice.lightspeedWired.calibrationKey(button: 9) == "g502x.physicalIndex.g9")
        let suite = "verify.mouse.device.\(ProcessInfo.processInfo.processIdentifier)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let buttons = Array(3...9)
        let base = MouseDevice.lightspeedReceiver.physicalIndexMap(buttons: buttons, store: store)
        precondition(base == MouseDevice.defaultPhysicalIndexToG)

        MouseDevice.g502xWired.saveCalibration(index: 12, button: 7, store: store)
        precondition(store.object(forKey: "g502x.physicalIndex.g7") == nil)
        let wiredMap = MouseDevice.g502xWired.physicalIndexMap(buttons: buttons, store: store)
        precondition(wiredMap[12] == 7 && wiredMap[10] == nil)
        precondition(
            MouseDevice.lightspeedWired.physicalIndexMap(buttons: buttons, store: store) == base
        )

        MouseDevice.lightspeedReceiver.saveCalibration(index: 11, button: 7, store: store)
        precondition(MouseDevice.g502xWired.physicalIndexMap(buttons: buttons, store: store)[12] == 7)
        precondition(
            MouseDevice.lightspeedReceiver.physicalIndexMap(buttons: buttons, store: store)[11] == 7
        )
        print("mouse device: selection, priority, flags and calibration keys")
    }
}
