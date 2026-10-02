import Foundation

@main
enum VerifyDesktopSwipeGesture {
    static func main() {
        var gesture = DesktopSwipeGesture(trigger: 6)
        precondition(!gesture.isTracking)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.isTracking)
        precondition(gesture.move(dx: 1, dy: 1) == .ignored)
        precondition(gesture.button(6, pressed: false) == .tap)
        precondition(!gesture.isTracking)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: -130, dy: 2) == .left)
        precondition(gesture.move(dx: -70, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 130, dy: -3) == .right)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 2, dy: 80) == .ignored)
        precondition(gesture.move(dx: 40, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: -119, dy: 0) == .ignored)
        precondition(gesture.move(dx: -1, dy: 0) == .left)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 20, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 80, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: true) == .ignored)
        precondition(gesture.move(dx: 45, dy: 0) == .right)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 100, dy: 90) == .ignored)
        precondition(gesture.move(dx: 30, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        precondition(gesture.button(5, pressed: true) == .ignored)
        precondition(gesture.button(5, pressed: false) == .ignored)
        precondition(!gesture.isTracking)
        precondition(gesture.move(dx: 100, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .ignored)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.button(4, pressed: true) == .ignored)
        precondition(gesture.isTracking)
        gesture.cancel()
        precondition(!gesture.isTracking)
        precondition(gesture.move(dx: 100, dy: 0) == .ignored)
        precondition(gesture.button(6, pressed: false) == .ignored)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 6, dy: 0) == .ignored)
        precondition(gesture.move(dx: -5, dy: 3) == .ignored)
        precondition(gesture.move(dx: 4, dy: -3) == .ignored)
        precondition(gesture.button(6, pressed: false) == .tap)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 7, dy: 7) == .ignored)
        precondition(gesture.button(6, pressed: false) == .tap)

        precondition(gesture.button(6, pressed: true) == .began)
        precondition(gesture.move(dx: 8, dy: 8) == .ignored)
        precondition(gesture.button(6, pressed: false) == .suppressed)

        var stiff = DesktopSwipeGesture(trigger: 6, activationDistance: 200)
        precondition(stiff.button(6, pressed: true) == .began)
        precondition(stiff.move(dx: 199, dy: 0) == .ignored)
        precondition(stiff.move(dx: 1, dy: 0) == .right)
        precondition(stiff.button(6, pressed: false) == .suppressed)

        var light = DesktopSwipeGesture(trigger: 6, activationDistance: 40)
        precondition(light.button(6, pressed: true) == .began)
        precondition(light.move(dx: -40, dy: 0) == .left)
        precondition(light.button(6, pressed: false) == .suppressed)

        precondition(DesktopSwipeGesture.clampedDistance(10) == 40)
        precondition(DesktopSwipeGesture.clampedDistance(999) == 300)
        precondition(DesktopSwipeGesture.clampedDistance(155) == 155)

        print("desktop swipe gesture: tap, swipes, cancellation and one-shot rules")
    }
}
