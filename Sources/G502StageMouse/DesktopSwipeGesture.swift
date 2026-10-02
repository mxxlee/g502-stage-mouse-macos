import Foundation

enum DesktopSwipeOutput: Equatable {
    case ignored
    case began
    case tap
    case left
    case right
    case suppressed
}

struct DesktopSwipeGesture {
    static let tapSlop = 10.0
    static let defaultActivationDistance = 120.0
    static let activationDistanceRange = 40.0...300.0
    static let horizontalDominance = 1.5

    let trigger: Int
    let activationDistance: Double
    private(set) var isTracking = false
    private var deltaX = 0.0
    private var deltaY = 0.0
    private var fired = false

    init(trigger: Int, activationDistance: Double = defaultActivationDistance) {
        self.trigger = trigger
        self.activationDistance = Self.clampedDistance(activationDistance)
    }

    static func clampedDistance(_ distance: Double) -> Double {
        min(max(distance, activationDistanceRange.lowerBound), activationDistanceRange.upperBound)
    }

    mutating func button(_ button: Int, pressed: Bool) -> DesktopSwipeOutput {
        guard button == trigger else { return .ignored }
        if pressed {
            guard !isTracking else { return .ignored }
            reset()
            isTracking = true
            return .began
        }
        guard isTracking else { return .ignored }
        let isTap = !fired && hypot(deltaX, deltaY) < Self.tapSlop
        reset()
        return isTap ? .tap : .suppressed
    }

    mutating func move(dx: Double, dy: Double) -> DesktopSwipeOutput {
        guard isTracking, !fired else { return .ignored }
        deltaX += dx
        deltaY += dy
        guard abs(deltaX) >= activationDistance,
              abs(deltaX) >= Self.horizontalDominance * abs(deltaY) else {
            return .ignored
        }
        fired = true
        return deltaX < 0 ? .left : .right
    }

    mutating func cancel() {
        reset()
    }

    private mutating func reset() {
        isTracking = false
        deltaX = 0
        deltaY = 0
        fired = false
    }
}
