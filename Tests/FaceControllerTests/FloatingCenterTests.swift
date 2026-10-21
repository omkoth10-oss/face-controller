import XCTest
@testable import FaceController

/// The floating center: follows a RESTING head near the center, never while
/// something is busy, outside the rest zone, or while the head is moving.
final class FloatingCenterTests: XCTestCase {
    private let zone = 2.0
    private let followTime = 1.5
    /// Where the head is resting (camera angles), and the matching player offset.
    private let head = HeadAngles(pitch: -1, yaw: 1, roll: 0.5)

    /// Runs the floating center for `duration` seconds at 30 fps; returns the center.
    private func simulate(duration: Double,
                          busy: String? = nil,
                          offset: (Int) -> PlayerHeadOffset,
                          center: inout FloatingCenter) -> HeadAngles {
        var neutral = HeadAngles.zero
        for (frame, time) in HeadMotion.frameTimes(duration: duration).enumerated() {
            center.update(neutral: &neutral, head: head, offset: offset(frame), zone: zone,
                          busyReason: busy, followTime: followTime, at: time)
        }
        return neutral
    }

    func testFollowsAHeadRestingNearTheCenter() {
        var center = FloatingCenter()
        let neutral = simulate(duration: 3, offset: { _ in PlayerHeadOffset(left: 1, up: 1) }, center: &center)
        XCTAssertTrue(center.isFollowing)
        // About 2.7 s of following with a 1.5 s follow time: most of the way there.
        XCTAssertGreaterThan(neutral.yaw, 0.7 * head.yaw)
        XCTAssertLessThan(neutral.yaw, head.yaw)
        XCTAssertLessThan(neutral.pitch, 0.7 * head.pitch)  // pitch is negative here
        XCTAssertGreaterThan(neutral.roll, 0.7 * head.roll)
    }

    func testWaitsForTheHeadToSettleFirst() {
        var center = FloatingCenter()
        // 0.2 s is shorter than the 0.25 s rest it needs before following.
        let neutral = simulate(duration: 0.2, offset: { _ in PlayerHeadOffset(left: 1, up: 1) }, center: &center)
        XCTAssertEqual(neutral, .zero)
        XCTAssertFalse(center.isFollowing)
    }

    func testNeverMovesWhileSomethingIsBusy() {
        var center = FloatingCenter()
        let neutral = simulate(duration: 3, busy: "A held",
                               offset: { _ in PlayerHeadOffset(left: 1, up: 1) }, center: &center)
        XCTAssertEqual(neutral, .zero)
        XCTAssertFalse(center.isFollowing)
        XCTAssertTrue(center.state.hasPrefix("paused"))
    }

    func testNeverMovesOutsideTheRestZone() {
        var center = FloatingCenter()
        let neutral = simulate(duration: 3, offset: { _ in PlayerHeadOffset(left: 5, up: 0) }, center: &center)
        XCTAssertEqual(neutral, .zero)
        XCTAssertFalse(center.isFollowing)
    }

    func testNeverMovesWhileTheHeadIsMoving() {
        var center = FloatingCenter()
        // Jiggling ±1.5° every frame: inside the zone, but far from still.
        let neutral = simulate(duration: 3,
                               offset: { frame in PlayerHeadOffset(left: frame % 2 == 0 ? 1.5 : -1.5, up: 0) },
                               center: &center)
        XCTAssertEqual(neutral, .zero)
        XCTAssertFalse(center.isFollowing)
    }

    func testResetForgetsTheRest() {
        var center = FloatingCenter()
        _ = simulate(duration: 1, offset: { _ in PlayerHeadOffset(left: 1, up: 1) }, center: &center)
        XCTAssertTrue(center.isFollowing)
        center.reset()
        XCTAssertFalse(center.isFollowing)
        XCTAssertEqual(center.speed, 0)
    }

    func testSettingsDecodeTolerantly() throws {
        // A save from before the Minecraft and Scroll switches existed.
        let json = #"{"keysEnabled": false, "followTime": 3}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FloatingCenterSettings.self, from: json)
        XCTAssertFalse(decoded.isEnabled(for: .keys))
        XCTAssertTrue(decoded.isEnabled(for: .minecraft))
        XCTAssertTrue(decoded.isEnabled(for: .scroll))
        XCTAssertEqual(decoded.followTime, 3)
    }
}
