import Foundation

enum Action: String, CaseIterable {
    case systemDefault = "none"
    case noAction
    case historyBack, historyForward
    case missionControl, appExpose
    case nextApp, previousApp
    case leftSpace, rightSpace
    case showDesktop

    init?(swipe output: DesktopSwipeOutput, reversed: Bool = false) {
        switch (output, reversed) {
        case (.left, false), (.right, true): self = .rightSpace
        case (.right, false), (.left, true): self = .leftSpace
        default: return nil
        }
    }

    var blocksNativeInput: Bool { self != .systemDefault }

    var replaysNativeClickOnShortPress: Bool { self == .systemDefault }

    func emulatedNavigationButton(forButton button: Int) -> UInt32? {
        guard self == .systemDefault else { return nil }
        switch button {
        case 4: return 3
        case 5: return 4
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .systemDefault: return L10n.string("action.systemDefault")
        case .noAction: return L10n.string("action.noAction")
        case .historyBack: return L10n.string("action.historyBack")
        case .historyForward: return L10n.string("action.historyForward")
        case .missionControl: return L10n.string("action.missionControl")
        case .appExpose: return L10n.string("action.appExpose")
        case .nextApp: return L10n.string("action.nextApp")
        case .previousApp: return L10n.string("action.previousApp")
        case .leftSpace: return L10n.string("action.leftSpace")
        case .rightSpace: return L10n.string("action.rightSpace")
        case .showDesktop: return L10n.string("action.showDesktop")
        }
    }
}
