import XCTest
@testable import FaceController

/// Head-to-mouse aiming: the response curve and the direction of the pointer.
/// (Only the math: the 120 Hz timer that actually moves the mouse isn't started.)
final class AimControllerTests: XCTestCase {
    private let deadzone = Config.Aim.horizontalDeadzone
    private let fullSpeed = Config.Aim.horizontalFullSpeedAngle
    private let maxSpeed = Config.Aim.maxSpeedX

    private func speed(_ angle: Double) -> Double {
        AimController.speed(for: angle, deadzone: deadzone, fullSpeedAngle: fullSpeed, maxSpeed: maxSpeed)
    }

    func testNothingInsideTheDeadzone() {
        XCTAssertEqual(speed(0), 0)
        XCTAssertEqual(speed(deadzone * 0.9), 0)
        XCTAssertEqual(speed(-deadzone), 0)
    }

    func testFullSpeedAtAndBeyondTheFullSpeedAngle() {
        XCTAssertEqual(speed(fullSpeed), maxSpeed, accuracy: 0.001)
        XCTAssertEqual(speed(fullSpeed * 3), maxSpeed, accuracy: 0.001)
        XCTAssertEqual(speed(-fullSpeed), -maxSpeed, accuracy: 0.001)
    }

    func testSpeedGrowsSmoothlyWithTheAngle() {
        var previous = 0.0
        for angle in stride(from: deadzone + 0.5, through: fullSpeed, by: 0.5) {
            let current = speed(angle)
            XCTAssertGreaterThan(current, previous, "faster at \(angle)°")
            previous = current
        }
        // The curve is slow near the deadzone (precise aim): halfway is well under half speed.
        let halfway = (deadzone + fullSpeed) / 2
        XCTAssertLessThan(speed(halfway), maxSpeed / 2)
    }

    func testPointerMovesTheSameWayAsTheHead() {
        let aim = AimController(input: VirtualInput())
        // Head turned to YOUR left and tilted up.
        let state = aim.update(offset: PlayerHeadOffset(left: 10, up: 6), at: 1)
        XCTAssertTrue(state.active)
        XCTAssertLessThan(state.speedX, 0, "pointer moves left")
        XCTAssertGreaterThan(state.speedY, 0, "pointer moves up")
        XCTAssertFalse(state.inDeadzoneX)
        XCTAssertFalse(state.inDeadzoneY)

        let other = aim.update(offset: PlayerHeadOffset(left: -10, up: -6), at: 2)
        XCTAssertGreaterThan(other.speedX, 0, "pointer moves right")
        XCTAssertLessThan(other.speedY, 0, "pointer moves down")
    }

    func testStillHeadKeepsThePointerStill() {
        let aim = AimController(input: VirtualInput())
        let state = aim.update(offset: PlayerHeadOffset(left: 1, up: -1), at: 1)
        XCTAssertEqual(state.speedX, 0)
        XCTAssertEqual(state.speedY, 0)
        XCTAssertTrue(state.inDeadzoneX)
        XCTAssertTrue(state.inDeadzoneY)
    }

    func testSensitivityScalesTheSpeedAndIsClamped() {
        let aim = AimController(input: VirtualInput())
        let normal = aim.update(offset: PlayerHeadOffset(left: 10, up: 0), at: 1).speedX
        aim.setSensitivity(2)
        let doubled = aim.update(offset: PlayerHeadOffset(left: 10, up: 0), at: 2).speedX
        XCTAssertEqual(doubled, normal * 2, accuracy: 0.001)
        aim.setSensitivity(100)
        XCTAssertEqual(aim.currentSensitivity, Config.Aim.sensitivityRange.upperBound)
    }
}

/// Camera angles → the player's left/right/up/down (the ONE place this happens).
final class PlayerDirectionsTests: XCTestCase {
    private var flipH: Double { Config.Directions.flipHorizontal ? -1 : 1 }
    private var flipV: Double { Config.Directions.flipVertical ? -1 : 1 }

    func testTiltUpIsNegativePitch() {
        let offset = PlayerDirections.offset(relative: HeadAngles(pitch: -5, yaw: 0, roll: 0), framesMirrored: false)
        XCTAssertEqual(offset.up, 5 * flipV)
        XCTAssertEqual(offset.left, 0)
    }

    func testTurnLeftIsPositiveYawInUnmirroredFrames() {
        let offset = PlayerDirections.offset(relative: HeadAngles(pitch: 0, yaw: 7, roll: 0), framesMirrored: false)
        XCTAssertEqual(offset.left, 7 * flipH)
    }

    func testMirroredFramesFlipLeftAndRightOnly() {
        let angles = HeadAngles(pitch: -5, yaw: 7, roll: 0)
        let normal = PlayerDirections.offset(relative: angles, framesMirrored: false)
        let mirrored = PlayerDirections.offset(relative: angles, framesMirrored: true)
        XCTAssertEqual(mirrored.left, -normal.left)
        XCTAssertEqual(mirrored.up, normal.up, "up/down never depends on mirroring")
    }

    func testShoulderTiltIsTheSameForEitherShoulder() {
        XCTAssertEqual(PlayerDirections.shoulderTilt(relative: HeadAngles(pitch: 0, yaw: 0, roll: 12)), 12)
        XCTAssertEqual(PlayerDirections.shoulderTilt(relative: HeadAngles(pitch: 0, yaw: 0, roll: -12)), 12)
    }
}
