import XCTest
@testable import FaceController

/// Hysteresis + hold time: the press/release logic behind Keys, Aim, Minecraft and
/// the mouth/eyebrow gestures. Values come in at 30 fps.
final class ThresholdGestureTests: XCTestCase {
    /// Press at 10, release below 6, hold 80 ms (the Keys mode head gesture).
    private func makeGesture() -> ThresholdGesture {
        ThresholdGesture(pressThreshold: 10, releaseThreshold: 6, holdTime: 0.080)
    }

    /// Feeds `values` one per frame (1/30 s apart) starting at `start`; returns the
    /// events with their times.
    private func feed(_ gesture: inout ThresholdGesture, _ values: [Double],
                      start: Double = 0) -> [(time: Double, event: GestureEvent)] {
        var events: [(time: Double, event: GestureEvent)] = []
        for (index, value) in values.enumerated() {
            let time = start + Double(index) / HeadMotion.frameRate
            if let event = gesture.update(value: value, at: time) {
                events.append((time, event))
            }
        }
        return events
    }

    func testStartsDisarmedUntilBackAtNeutral() {
        var gesture = makeGesture()
        XCTAssertEqual(gesture.phase, .waitingForNeutral)
        // Already past the threshold when it starts: must NOT press.
        XCTAssertTrue(feed(&gesture, Array(repeating: 12, count: 30)).isEmpty)
        // Back to neutral arms it.
        _ = feed(&gesture, [0], start: 1.0)
        XCTAssertEqual(gesture.phase, .ready)
    }

    func testPressesOnlyAfterTheHoldTime() {
        var gesture = makeGesture()
        // Frame 0 arms it; from frame 1 the value is past the threshold.
        let events = feed(&gesture, [0] + Array(repeating: 12, count: 10))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, .press)
        // Crossed at 1/30 s; 80 ms later is the 4th frame (4/30 s).
        XCTAssertEqual(events.first?.time ?? 0, 4.0 / 30.0, accuracy: 0.001)
        XCTAssertTrue(gesture.isActive)
    }

    func testShortTwitchIsIgnored() {
        var gesture = makeGesture()
        // Two frames past the threshold (~67 ms) is shorter than the 80 ms hold.
        XCTAssertTrue(feed(&gesture, [0, 12, 12, 0, 0, 0]).isEmpty)
        XCTAssertEqual(gesture.phase, .ready)
    }

    func testHysteresisKeepsItHeldBetweenTheThresholds() {
        var gesture = makeGesture()
        _ = feed(&gesture, [0, 12, 12, 12, 12])
        XCTAssertTrue(gesture.isActive)
        // Hovering between release (6) and press (10): stays held, no flicker.
        XCTAssertTrue(feed(&gesture, [9, 7, 8, 6.5, 9], start: 1).isEmpty)
        XCTAssertTrue(gesture.isActive)
        // Below release: let go at once.
        let events = feed(&gesture, [5], start: 2)
        XCTAssertEqual(events.map { $0.event }, [.release])
        XCTAssertFalse(gesture.isActive)
    }

    func testCancelHoldStopsAHoldInProgress() {
        var gesture = makeGesture()
        _ = feed(&gesture, [0, 12])
        if case .holding = gesture.phase {} else { XCTFail("should be holding") }
        gesture.cancelHold()
        XCTAssertEqual(gesture.phase, .ready)
    }

    func testResetRequiringNeutralDisarms() {
        var gesture = makeGesture()
        _ = feed(&gesture, [0, 12, 12, 12, 12])
        XCTAssertTrue(gesture.isActive)
        gesture.reset(requireNeutral: true)
        XCTAssertEqual(gesture.phase, .waitingForNeutral)
        // Still past the threshold: nothing fires until it comes back.
        XCTAssertTrue(feed(&gesture, Array(repeating: 12, count: 10), start: 1).isEmpty)
    }

    func testReleaseThresholdIsNeverAbovePress() {
        let gesture = ThresholdGesture(pressThreshold: 5, releaseThreshold: 9, holdTime: 0)
        XCTAssertLessThanOrEqual(gesture.releaseThreshold, gesture.pressThreshold)
    }
}
