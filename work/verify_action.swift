import Foundation

@main
enum VerifyAction {
    static func main() {
        precondition(Action(rawValue: "none") == .systemDefault)
        precondition(Action.systemDefault.rawValue == "none")
        precondition(Action(rawValue: "noAction") == .noAction)
        precondition(Action.allCases.prefix(2) == [.systemDefault, .noAction])
        precondition(Set(Action.allCases.map(\.rawValue)).count == Action.allCases.count)

        precondition(!Action.systemDefault.blocksNativeInput)
        precondition(Action.systemDefault.replaysNativeClickOnShortPress)
        for action in Action.allCases where action != .systemDefault {
            precondition(action.blocksNativeInput)
            precondition(!action.replaysNativeClickOnShortPress)
        }
        precondition(Action(swipe: .left) == .rightSpace)
        precondition(Action(swipe: .right) == .leftSpace)
        precondition(Action(swipe: .left, reversed: false) == .rightSpace)
        precondition(Action(swipe: .left, reversed: true) == .leftSpace)
        precondition(Action(swipe: .right, reversed: true) == .rightSpace)
        precondition(Action(swipe: .tap, reversed: true) == nil)
        precondition(Action(swipe: .ignored) == nil)
        precondition(Action(swipe: .tap) == nil)
        precondition(Action.systemDefault.emulatedNavigationButton(forButton: 4) == 3)
        precondition(Action.systemDefault.emulatedNavigationButton(forButton: 5) == 4)
        precondition(Action.systemDefault.emulatedNavigationButton(forButton: 6) == nil)
        precondition(Action.systemDefault.emulatedNavigationButton(forButton: 3) == nil)
        for action in Action.allCases where action != .systemDefault {
            precondition(action.emulatedNavigationButton(forButton: 4) == nil)
            precondition(action.emulatedNavigationButton(forButton: 5) == nil)
        }
        precondition(DockNotification.isAvailable)
        print("action: system default keeps native input, no action blocks it")
    }
}
