import XCTest
@testable import FaceController

/// Scroll mode: the smooth-scroll math (tilt → speed, easing, points) and the
/// Shorts flicks (Snake's tap logic with Shorts settings).
final class ScrollMotionTests: XCTestCase {
    private let settings = ScrollSettings()
    /// The scroll timer's step.
    private let tick = 1.0 / Config.Scroll.outputRate

    private func target(up: Double, _ settings: ScrollSettings? = nil) -> Double {
        ScrollMotion.targetSpeed(up: up, settings: settings ?? self.settings)
    }

    func testDeadzoneMeansNoScrolling() {
        XCTAssertEqual(target(up: 0), 0)
        XCTAssertEqual(target(up: settings.deadzoneDegrees * 0.9), 0)
        XCTAssertEqual(target(up: -settings.deadzoneDegrees), 0)
    }

    func testTiltDownScrollsDownAndUpScrollsUp() {
        XCTAssertGreaterThan(target(up: -10), 0, "+ = down the page")
        XCTAssertLessThan(target(up: 10), 0)
        XCTAssertEqual(target(up: -10), -target(up: 10), accuracy: 1e-9)
    }

    func testFurtherTiltScrollsFasterUpToFullSpeed() {
        var previous = 0.0
        for degrees in stride(from: settings.deadzoneDegrees + 0.5, through: Config.Scroll.fullSpeedDegrees, by: 0.5) {
            let speed = target(up: -degrees)
            XCTAssertGreaterThan(speed, previous)
            previous = speed
        }
        XCTAssertEqual(target(up: -Config.Scroll.fullSpeedDegrees), Config.Scroll.maxSpeed, accuracy: 0.001)
        XCTAssertEqual(target(up: -40), Config.Scroll.maxSpeed, accuracy: 0.001, "capped at full speed")
        // Gentle just past the deadzone, for reading.
        XCTAssertLessThan(target(up: -(settings.deadzoneDegrees + 1)), 0.02 * Config.Scroll.maxSpeed)
    }

    func testSpeedSliderAndReverseSwitch() {
        var faster = settings
        faster.speed = 2
        XCTAssertEqual(target(up: -10, faster), 2 * target(up: -10), accuracy: 1e-6)
        var reversed = settings
        reversed.reverse = true
        XCTAssertEqual(target(up: -10, reversed), -target(up: -10), accuracy: 1e-9)
    }

    func testBiggerDeadzoneNeedsMoreTilt() {
        var wide = settings
        wide.deadzoneDegrees = 8
        XCTAssertEqual(target(up: -7, wide), 0)
        XCTAssertGreaterThan(target(up: -7), 0)
    }

    func testSpeedsUpSmoothlyInsteadOfJumping() {
        var motion = ScrollMotion()
        let goal = 1000.0
        var previous = 0.0
        for step in 1...120 {  // one second
            _ = motion.step(toward: goal, dt: tick)
            let change = motion.speed - previous
            XCTAssertGreaterThanOrEqual(change, 0)
            XCTAssertLessThanOrEqual(change, goal * tick / Config.Scroll.speedUpTime + 1e-9,
                                     "no jump at step \(step)")
            previous = motion.speed
            if step == 1 {
                XCTAssertLessThan(motion.speed, 0.05 * goal, "the first moment is gentle")
            }
        }
        XCTAssertGreaterThan(motion.speed, 0.95 * goal, "close to full speed after a second")
    }

    func testStopsPromptlyWhenTheHeadComesBack() {
        var motion = ScrollMotion()
        for _ in 0..<240 { _ = motion.step(toward: 1000, dt: tick) }
        var scrolledWhileStopping = 0
        for _ in 0..<Int(0.6 * Config.Scroll.outputRate) {
            scrolledWhileStopping += motion.step(toward: 0, dt: tick)
        }
        XCTAssertEqual(motion.speed, 0, "stopped within 0.6 s")
        XCTAssertEqual(motion.step(toward: 0, dt: tick), 0)
        XCTAssertLessThan(scrolledWhileStopping, 200, "a short glide, not a long coast")
    }

    func testSlowScrollingStillAddsUp() {
        // 30 points per second is less than one point per 120 Hz step.
        var motion = ScrollMotion()
        for _ in 0..<240 { _ = motion.step(toward: 30, dt: tick) }  // reach the speed
        var total = 0
        for _ in 0..<120 { total += motion.step(toward: 30, dt: tick) }  // then one second
        XCTAssertEqual(Double(total), 30, accuracy: 2)
    }

    func testScrollsUpWithNegativePoints() {
        var motion = ScrollMotion()
        var total = 0
        for _ in 0..<240 { total += motion.step(toward: -500, dt: tick) }
        XCTAssertLessThan(total, 0)
    }

    func testResetStopsDead() {
        var motion = ScrollMotion()
        for _ in 0..<60 { _ = motion.step(toward: 800, dt: tick) }
        motion.reset()
        XCTAssertEqual(motion.speed, 0)
        XCTAssertEqual(motion.step(toward: 0, dt: tick), 0)
    }
}

final class ScrollSettingsTests: XCTestCase {
    func testBindingsPerOption() {
        var settings = ScrollSettings()
        settings.option = .smooth
        settings.mouthPlayPauseEnabled = true
        XCTAssertEqual(Set(settings.bindings.keys), [.mouthOpen], "smooth scrolling isn't a key")

        settings.option = .shorts
        XCTAssertEqual(Set(settings.bindings.keys), [.tiltDown, .tiltUp, .mouthOpen])
        XCTAssertEqual(settings.bindings[.tiltDown]?.style, .tap)
        XCTAssertEqual(settings.bindings[.tiltDown]?.action, Config.Scroll.nextShort.action)
        XCTAssertEqual(settings.bindings[.tiltUp]?.action, Config.Scroll.previousShort.action)

        settings.mouthPlayPauseEnabled = false
        XCTAssertNil(settings.bindings[.mouthOpen])
    }

    func testDecodesTolerantly() throws {
        let json = #"{"option": "warpSpeed", "speed": 2}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScrollSettings.self, from: json)
        XCTAssertEqual(decoded.option, Config.Scroll.defaultOption, "unknown option → default")
        XCTAssertEqual(decoded.speed, 2)
        XCTAssertEqual(decoded.deadzoneDegrees, Config.Scroll.defaultDeadzoneDegrees)
    }

    func testClamped() {
        var wild = ScrollSettings()
        wild.deadzoneDegrees = 0
        wild.speed = 99
        XCTAssertEqual(wild.clamped().deadzoneDegrees, Config.Scroll.deadzoneRange.lowerBound)
        XCTAssertEqual(wild.clamped().speed, Config.Scroll.speedRange.upperBound)
    }
}

/// Shorts: one nod = exactly one video. Same tap logic as Snake, Shorts settings.
final class ShortsTests: XCTestCase {
    private let settings = SnakeSettings.shortsDefaults

    private func nodDown(_ t: Double, start: Double, overshoot: Double = 0) -> Double {
        -HeadMotion.turn(t, start: start, amplitude: 15, overshoot: overshoot)
    }

    func testShortsDefaultsBlockBounceAndDoubleFlicks() {
        XCTAssertTrue(settings.bounceBlockEnabled)
        XCTAssertTrue(settings.sameDirectionBlockEnabled)
        XCTAssertTrue(settings.extraTurnGuardEnabled)
        XCTAssertEqual(settings.holdTime, Config.Scroll.shortsHoldTime, accuracy: 1e-9)
        XCTAssertEqual(settings.pressDegrees, SnakeSettings().pressDegrees)
    }

    func testOneNodDownIsOneNextVideo() {
        let run = TapRun.run(settings: settings, duration: 1.6) { t in
            PlayerHeadOffset(left: 0, up: self.nodDown(t, start: 0.2, overshoot: 4))
        }
        XCTAssertEqual(run.verticalTurns, [.tiltDown])
    }

    func testBigSwingBackDoesNotGoBackAVideo() {
        // The head swings 10° past the center on the way back: still only NEXT.
        let run = TapRun.run(settings: settings, duration: 1.6) { t in
            PlayerHeadOffset(left: 0, up: self.nodDown(t, start: 0.2, overshoot: 10))
        }
        XCTAssertEqual(run.verticalTurns, [.tiltDown])
        XCTAssertTrue(run.blocked.contains { $0.gesture == .tiltUp && $0.reason.contains("bounce-back") },
                      "the swing back is blocked and reported")
    }

    func testTenNodsAreTenVideos() {
        let run = TapRun.run(settings: settings, duration: 8.6) { t in
            var up = 0.0
            for nod in 0..<10 {
                up += self.nodDown(t, start: 0.2 + 0.8 * Double(nod), overshoot: 3)
            }
            return PlayerHeadOffset(left: 0, up: up)
        }
        XCTAssertEqual(run.verticalTurns, Array(repeating: GestureID.tiltDown, count: 10))
    }

    func testOneNodUpIsOnePreviousVideo() {
        let run = TapRun.run(settings: settings, duration: 1.5) { t in
            PlayerHeadOffset(left: 0, up: HeadMotion.turn(t, start: 0.2, amplitude: 12, overshoot: 3))
        }
        XCTAssertEqual(run.verticalTurns, [.tiltUp])
    }

    func testLookingAwaySidewaysNeverChangesTheVideo() {
        // A fast 25° turn to the side that tips the head up a little (20%).
        let run = TapRun.run(settings: settings, duration: 1.5) { t in
            let turn = HeadMotion.turn(t, start: 0.2, amplitude: 25, overshoot: 3)
            return PlayerHeadOffset(left: turn, up: 0.2 * HeadMotion.turn(t, start: 0.2, amplitude: 25))
        }
        XCTAssertEqual(run.verticalTurns, [], "left/right is never sent in Shorts, and the leak is ignored")
    }
}
