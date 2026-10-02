import Foundation

enum DockNotification {
    private typealias SendFunction = @convention(c) (CFString, Int32) -> Void

    private static let send: SendFunction? = {
        let framework = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(framework, RTLD_NOW),
              let symbol = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(symbol, to: SendFunction.self)
    }()

    static var isAvailable: Bool { send != nil }

    @discardableResult
    static func post(_ name: String) -> Bool {
        guard let send else { return false }
        send(name as CFString, 0)
        return true
    }

    @discardableResult
    static func toggleShowDesktop() -> Bool {
        post("com.apple.showdesktop.awake")
    }

    @discardableResult
    static func toggleAppExpose() -> Bool {
        post("com.apple.expose.front.awake")
    }
}
