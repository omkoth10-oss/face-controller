import XCTest
@testable import FaceController

/// Minecraft preset (Phase 3): option 2's tilt-to-a-shoulder switch, and what each
/// option binds.
final class HeadOptionsTests: XCTestCase {
    /// Feeds a shoulder tilt for `duration` seconds at 30 fps; returns how many switches.
    private func tilt(_ degrees: Double, for duration: Double, start: Double,
                      switcher: inout HeadJobSwitch) -> Int {
        var switches = 0
        for time in HeadMotion.frameTimes(duration: duration) {
            if switcher.update(tilt: degrees, at: start + time) { switches += 1 }
        }
        return switches
    }

    func testOneTiltIsOneSwitch() {
        var switcher = HeadJobSwitch(tiltDegrees: 15)
        XCTAssertEqual(switcher.job, Config.Minecraft.startHeadJob)
        XCTAssertEqual(tilt(0, for: 0.2, start: 0, switcher: &switcher), 0)  // arm it
        // Holding the tilt for a second switches ONCE, not over and over.
        XCTAssertEqual(tilt(20, for: 1, start: 0.3, switcher: &switcher), 1)
        XCTAssertEqual(switcher.job, Config.Minecraft.startHeadJob.other)
        XCTAssertTrue(switcher.isTilting)
        // Upright again, then a second tilt switches back.
        XCTAssertEqual(tilt(0, for: 0.3, start: 1.5, switcher: &switcher), 0)
        XCTAssertFalse(switcher.isTilting)
        XCTAssertEqual(tilt(20, for: 0.5, start: 2, switcher: &switcher), 1)
        XCTAssertEqual(switcher.job, Config.Minecraft.startHeadJob)
        XCTAssertEqual(switcher.switchCount, 2)
    }

    func testAQuickWobbleDoesNotSwitch() {
        var switcher = HeadJobSwitch(tiltDegrees: 15)
        _ = tilt(0, for: 0.2, start: 0, switcher: &switcher)
        // 0.1 s past the tilt is shorter than the 0.15 s hold.
        XCTAssertEqual(tilt(20, for: 0.1, start: 0.3, switcher: &switcher), 0)
        XCTAssertEqual(tilt(0, for: 0.2, start: 0.45, switcher: &switcher), 0)
        XCTAssertEqual(switcher.job, Config.Minecraft.startHeadJob)
    }

    func testSmallTiltNeverSwitches() {
        var switcher = HeadJobSwitch(tiltDegrees: 15)
        _ = tilt(0, for: 0.2, start: 0, switcher: &switcher)
        XCTAssertEqual(tilt(12, for: 2, start: 0.3, switcher: &switcher), 0)
        XCTAssertTrue(switcher.isTilting, "past half the switch tilt: moving/aiming pause")
    }

    func testBindingsPerOption() {
        var settings = MinecraftSettings()

        settings.option = .faceMoves
        var bindings = settings.bindings(job: .aim)
        XCTAssertEqual(bindings[.mouthOpen]?.action, Config.Minecraft.walkForward.action)
        XCTAssertEqual(bindings[.eyebrowsRaise]?.action, Config.Minecraft.jump.action)
        XCTAssertNil(bindings[.tiltUp], "the head only aims")
        XCTAssertTrue(settings.headAims(job: .move))

        settings.option = .modeSwitch
        bindings = settings.bindings(job: .move)
        XCTAssertEqual(bindings[.tiltUp]?.action, Config.Minecraft.walkForward.action)
        XCTAssertEqual(bindings[.turnLeft]?.action, Config.Minecraft.walkLeft.action)
        XCTAssertEqual(bindings[.mouthOpen]?.action, Config.Minecraft.breakBlock.action)
        XCTAssertFalse(settings.headAims(job: .move))
        XCTAssertNil(settings.bindings(job: .aim)[.tiltUp], "in AIM the head doesn't walk")
        XCTAssertTrue(settings.headAims(job: .aim))

        settings.option = .splitZones
        bindings = settings.bindings(job: .aim)
        XCTAssertEqual(bindings[.tiltDown]?.action, Config.Minecraft.walkBack.action)
        XCTAssertTrue(settings.headAims(job: .aim), "aims AND walks")
        XCTAssertEqual(settings.headWalkThresholds?.press, settings.walkZoneDegrees)
    }

    func testDecodesTolerantly() throws {
        let json = #"{"option": "teleport", "walkZoneDegrees": 13}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MinecraftSettings.self, from: json)
        XCTAssertEqual(decoded.option, Config.Minecraft.defaultOption)
        XCTAssertEqual(decoded.walkZoneDegrees, 13)
        XCTAssertEqual(decoded.switchTiltDegrees, Config.Minecraft.defaultSwitchTiltDegrees)
    }
}
