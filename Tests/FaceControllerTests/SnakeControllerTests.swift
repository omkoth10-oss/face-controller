import XCTest
@testable import FaceController

/// Snake mode's turn logic, driven by simulated 30 fps head motion.
/// Uses the default settings (the owner's tuned values: press 8.5°, flick 80°/s...).
final class SnakeControllerTests: XCTestCase {
    private let settings = SnakeSettings()

    private func offset(left: Double = 0, up: Double = 0) -> PlayerHeadOffset {
        PlayerHeadOffset(left: left, up: up)
    }

    func testDefaultsAreTheOwnersTunedValues() {
        XCTAssertEqual(settings.pressDegrees, 8.5)
        XCTAssertEqual(settings.rearmFraction, 0.45)
        XCTAssertEqual(settings.holdTime, 0.040, accuracy: 1e-9)
        XCTAssertEqual(settings.smoothing, 0.25)
        XCTAssertEqual(settings.flickSpeed, 80)
        XCTAssertEqual(settings.minTurnInterval, 0.045, accuracy: 1e-9)
        XCTAssertTrue(settings.extraTurnGuardEnabled)
        XCTAssertFalse(settings.bounceBlockEnabled)
        XCTAssertFalse(settings.sameDirectionBlockEnabled)
    }

    func testOneQuickFlickIsExactlyOneTurn() {
        let run = TapRun.run(settings: settings, duration: 2) { t in
            self.offset(left: HeadMotion.turn(t, start: 0.2, amplitude: 15))
        }
        XCTAssertEqual(run.turnGestures, [.turnLeft])
        XCTAssertTrue(run.turns[0].viaFlick)
        XCTAssertTrue(run.blocked.isEmpty)
    }

    func testFlickFiresEarlyBeforeThePressThreshold() throws {
        // The flick fires on the way out, long before the head stops at 15°.
        let run = TapRun.run(settings: settings, duration: 1) { t in
            self.offset(left: HeadMotion.turn(t, start: 0.2, amplitude: 15))
        }
        let turn = try XCTUnwrap(run.turns.first)
        XCTAssertLessThan(turn.time, 0.2 + 0.12, "fired before the head reached its furthest point")
    }

    func testSlowTiltFiresByPositionAfterTheHoldTime() {
        let run = TapRun.run(settings: settings, duration: 2) { t in
            self.offset(up: HeadMotion.ramp(t, start: 0.2, to: 12, rise: 0.8))
        }
        XCTAssertEqual(run.turnGestures, [.tiltUp])
        XCTAssertFalse(run.turns[0].viaFlick, "too slow to be a flick")
    }

    func testSmallSlowMovementBelowThePressThresholdDoesNothing() {
        let run = TapRun.run(settings: settings, duration: 2) { t in
            self.offset(up: HeadMotion.ramp(t, start: 0.2, to: 6, rise: 0.8))
        }
        XCTAssertTrue(run.turns.isEmpty)
    }

    func testSameDirectionAgainNeedsARearmFirst() {
        // Left, come back only to 6° (re-arm is below 3.8°), then left again.
        let run = TapRun.run(settings: settings, duration: 1.6) { t in
            let left: Double
            if t < 0.2 { left = 0 }
            else if t < 0.5 { left = 15 * min(1, (t - 0.2) / 0.1) }
            else if t < 0.9 { left = 15 - 9 * min(1, (t - 0.5) / 0.15) }
            else { left = 6 + 9 * min(1, (t - 0.9) / 0.1) }
            return self.offset(left: left)
        }
        XCTAssertEqual(run.turnGestures, [.turnLeft])
        XCTAssertTrue(run.blocked.contains { $0.gesture == .turnLeft && $0.reason.contains("not re-armed") },
                      "the second attempt is reported, not silently dropped")
    }

    func testFastComboFiresEveryTurnInOrder() {
        // Right, then down, then left, each half a second apart.
        let run = TapRun.run(settings: settings, duration: 2.2) { t in
            self.offset(left: -HeadMotion.turn(t, start: 0.2, amplitude: 14) + HeadMotion.turn(t, start: 1.2, amplitude: 14),
                        up: -HeadMotion.turn(t, start: 0.7, amplitude: 14))
        }
        XCTAssertEqual(run.turnGestures, [.turnRight, .tiltDown, .turnLeft])
    }

    func testDiagonalFiresBothTurns() {
        let run = TapRun.run(settings: settings, duration: 1.5) { t in
            self.offset(left: HeadMotion.turn(t, start: 0.2, amplitude: 14),
                        up: HeadMotion.turn(t, start: 0.2, amplitude: 12))
        }
        XCTAssertEqual(Set(run.turnGestures), [.turnLeft, .tiltUp])
        XCTAssertEqual(run.turns.count, 2)
    }

    func testExtraTurnGuardIgnoresSmallSwingBack() {
        // A big left with a 4° swing past the center on the way back.
        let run = TapRun.run(settings: settings, duration: 2) { t in
            self.offset(left: HeadMotion.turn(t, start: 0.2, amplitude: 25, overshoot: 4))
        }
        XCTAssertEqual(run.turnGestures, [.turnLeft], "no extra RIGHT from the swing back")
        XCTAssertTrue(run.blocked.contains { $0.gesture == .turnRight && $0.isExtraTurn },
                      "the ignored swing-back is reported (orange line)")
    }

    func testWithoutTheGuardTheSwingBackWouldTurn() {
        // Shows what the guard prevents: the same movement with the guard off.
        var noGuard = settings
        noGuard.extraTurnGuardEnabled = false
        let run = TapRun.run(settings: noGuard, duration: 2) { t in
            self.offset(left: HeadMotion.turn(t, start: 0.2, amplitude: 25, overshoot: 4))
        }
        XCTAssertEqual(run.turnGestures, [.turnLeft, .turnRight])
    }

    func testExtraTurnGuardIgnoresLeakIntoTheOtherAxis() {
        // A fast turn right that also tips the head down a little (20% of the turn).
        let run = TapRun.run(settings: settings, duration: 1.5) { t in
            let right = HeadMotion.turn(t, start: 0.2, amplitude: 20, overshoot: 2)
            return self.offset(left: -right, up: -0.2 * HeadMotion.turn(t, start: 0.2, amplitude: 20))
        }
        XCTAssertEqual(run.turnGestures, [.turnRight], "no extra DOWN from the leak")
    }

    func testAfterASafetyResetTheHeadMustComeBackFirst() {
        // Not armed (like after calibration or a lost face): a head already turned
        // 12° must not fire. After coming back to center, a new flick works.
        let run = TapRun.run(settings: settings, duration: 2, arm: false) { t in
            self.offset(left: (t < 1.0 ? 12 : 0) + HeadMotion.turn(t, start: 1.3, amplitude: 15))
        }
        XCTAssertEqual(run.turnGestures, [.turnLeft])
        XCTAssertGreaterThan(run.turns[0].time, 1.3)
    }

    // MARK: - Saved settings

    func testSavedSettingsDecodeTolerantly() throws {
        // An old save with one value and a key that no longer exists.
        let json = #"{"pressDegrees": 6.5, "driftCorrection": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SnakeSettings.self, from: json)
        XCTAssertEqual(decoded.pressDegrees, 6.5)
        XCTAssertEqual(decoded.flickSpeed, SnakeSettings().flickSpeed, "missing values get defaults")
        XCTAssertTrue(decoded.extraTurnGuardEnabled)
    }

    func testSettingsSurviveARoundTrip() throws {
        var custom = SnakeSettings()
        custom.pressDegrees = 7
        custom.bounceBlockEnabled = true
        let data = try JSONEncoder().encode(custom)
        XCTAssertEqual(try JSONDecoder().decode(SnakeSettings.self, from: data), custom)
    }

    func testClampedKeepsValuesInsideTheSliderRanges() {
        var wild = SnakeSettings()
        wild.pressDegrees = 50
        wild.flickSpeed = -10
        let clamped = wild.clamped()
        XCTAssertEqual(clamped.pressDegrees, Config.Snake.pressRange.upperBound)
        XCTAssertEqual(clamped.flickSpeed, Config.Snake.flickSpeedRange.lowerBound)
    }
}
