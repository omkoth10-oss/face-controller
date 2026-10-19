import Foundation

// MARK: - The three options (Phase 3: one head, two jobs)

/// How the head shares MOVING and AIMING in the Minecraft preset. Phase 3 is about
/// trying all three in a real game and keeping the one that plays best.
enum HeadOption: String, Codable, CaseIterable, Identifiable {
    /// 1. The head only aims (mouse look). The face walks: mouth open = W, eyebrows = jump.
    case faceMoves
    /// 2. A quick tilt toward a shoulder flips the head between MOVE (W A S D) and AIM.
    case modeSwitch
    /// 3. Small head moves aim; past a bigger "walk zone" the head ALSO walks that way.
    case splitZones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faceMoves: return "1. Face moves, head aims"
        case .modeSwitch: return "2. Mode switch"
        case .splitZones: return "3. Split zones"
        }
    }

    /// Fits in the segmented picker.
    var shortTitle: String {
        switch self {
        case .faceMoves: return "1 Face moves"
        case .modeSwitch: return "2 Mode switch"
        case .splitZones: return "3 Split zones"
        }
    }
}

/// Option 2: what the head is doing right now.
enum HeadJob: String, Codable {
    /// Head turns/tilts hold W A S D.
    case move
    /// Head moves the mouse (looks around).
    case aim

    var title: String {
        switch self {
        case .move: return "MOVE"
        case .aim: return "AIM"
        }
    }

    var other: HeadJob { self == .move ? .aim : .move }
}

// MARK: - Settings (saved between launches)

/// Minecraft preset settings: which option, and its few tunable numbers.
/// Saved in UserDefaults, read tolerantly (like the Snake settings).
struct MinecraftSettings: Codable, Equatable {
    var option = Config.Minecraft.defaultOption
    /// Option 2: tilt toward a shoulder this far to switch MOVE ↔ AIM.
    var switchTiltDegrees = Config.Minecraft.defaultSwitchTiltDegrees
    /// Option 2: in MOVE, turn/tilt this far to walk.
    var moveDegrees = Config.Minecraft.defaultMoveDegrees
    /// Option 3: past this, the head walks as well as aims.
    var walkZoneDegrees = Config.Minecraft.defaultWalkZoneDegrees
    /// Show the small MOVE/AIM label over the game.
    var overlayEnabled = Config.Minecraft.defaultOverlayEnabled

    enum CodingKeys: String, CodingKey {
        case option, switchTiltDegrees, moveDegrees, walkZoneDegrees, overlayEnabled
    }

    /// Does the head move the mouse right now?
    func headAims(job: HeadJob) -> Bool {
        option != .modeSwitch || job == .aim
    }

    /// What every gesture does right now (option 2 depends on the head's job).
    func bindings(job: HeadJob) -> [GestureID: OutputBinding] {
        let walkWithHead = Config.Minecraft.actionBindings
            .merging(Config.Minecraft.headWalkBindings) { action, _ in action }
        switch option {
        case .faceMoves:
            return Config.Minecraft.faceMovesBindings
        case .modeSwitch:
            return job == .move ? walkWithHead : Config.Minecraft.actionBindings
        case .splitZones:
            return walkWithHead
        }
    }

    /// When the head walks: how far to press, and where it lets go (hysteresis).
    var headWalkThresholds: GestureThresholds? {
        switch option {
        case .faceMoves:
            return nil
        case .modeSwitch:
            return GestureThresholds(press: moveDegrees,
                                     release: moveDegrees * Config.Minecraft.moveReleaseFraction,
                                     holdTime: Config.Minecraft.moveHoldTime)
        case .splitZones:
            return GestureThresholds(press: walkZoneDegrees,
                                     release: walkZoneDegrees * Config.Minecraft.walkReleaseFraction,
                                     holdTime: Config.Minecraft.walkHoldTime)
        }
    }

    func clamped() -> MinecraftSettings {
        var copy = self
        copy.switchTiltDegrees = Self.clamp(switchTiltDegrees, Config.Minecraft.switchTiltRange)
        copy.moveDegrees = Self.clamp(moveDegrees, Config.Minecraft.moveRange)
        copy.walkZoneDegrees = Self.clamp(walkZoneDegrees, Config.Minecraft.walkZoneRange)
        return copy
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Saving

    private static let storageKey = "minecraftSettings.v1"

    static func load() -> MinecraftSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(MinecraftSettings.self, from: data) else {
            return MinecraftSettings()
        }
        return saved.clamped()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension MinecraftSettings {
    /// Reads saved values, filling in defaults for anything missing or unknown, so a
    /// later update never wipes the values you already saved.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MinecraftSettings()
        // `try?`: an option name this version doesn't know falls back to the default.
        option = (try? container.decodeIfPresent(HeadOption.self, forKey: .option)) ?? defaults.option
        switchTiltDegrees = try container.decodeIfPresent(Double.self, forKey: .switchTiltDegrees)
            ?? defaults.switchTiltDegrees
        moveDegrees = try container.decodeIfPresent(Double.self, forKey: .moveDegrees) ?? defaults.moveDegrees
        walkZoneDegrees = try container.decodeIfPresent(Double.self, forKey: .walkZoneDegrees)
            ?? defaults.walkZoneDegrees
        overlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? defaults.overlayEnabled
    }
}

// MARK: - Option 2's switch gesture

/// Option 2's switch: tilt your head toward EITHER shoulder (like a curious dog),
/// hold it a moment, and the head's job flips between MOVE and AIM.
///
/// Why this gesture: walking and aiming only use turning (left/right) and nodding
/// (up/down). Tilting toward a shoulder is a third, separate movement that Vision
/// measures very reliably, and people rarely do it by accident while playing.
///
///   tilt ──▶ past the switch tilt for the hold time ──▶ SWITCH ──▶ come back below
///            half of it before the next switch is possible
///
/// While the head is tilted past half the switch tilt, the engine pauses the head's
/// moving and aiming, so the gesture itself never walks or turns the camera.
struct HeadJobSwitch {
    private(set) var job: HeadJob = Config.Minecraft.startHeadJob
    /// Latest tilt (degrees toward either shoulder, from neutral).
    private(set) var tilt: Double = 0
    private(set) var switchCount = 0
    private(set) var tiltDegrees: Double
    private var detector: ThresholdGesture

    init(tiltDegrees: Double) {
        self.tiltDegrees = tiltDegrees
        detector = Self.makeDetector(tiltDegrees)
    }

    /// Head tilted far enough that moving/aiming should pause.
    var isTilting: Bool { tilt >= tiltDegrees * Config.Minecraft.switchPauseFraction }

    var phase: GesturePhase { detector.phase }

    /// Feeds one frame. Returns true when the job just switched.
    mutating func update(tilt: Double, at time: Double) -> Bool {
        self.tilt = tilt
        guard detector.update(value: tilt, at: time) == .press else { return false }
        toggle()
        return true
    }

    /// Flip MOVE ↔ AIM (the gesture, or the "Switch now" button).
    mutating func toggle() {
        job = job.other
        switchCount += 1
    }

    /// New switch tilt from the slider (keeps the current job).
    mutating func setTiltDegrees(_ degrees: Double) {
        tiltDegrees = degrees
        detector = Self.makeDetector(degrees)
    }

    /// After a safety reset (face lost, recenter...): the head must come back from
    /// any tilt before it can switch again. Keeps the current job.
    mutating func requireNeutral() {
        detector.reset(requireNeutral: true)
    }

    private static func makeDetector(_ degrees: Double) -> ThresholdGesture {
        ThresholdGesture(pressThreshold: degrees,
                         releaseThreshold: degrees * Config.Minecraft.switchReleaseFraction,
                         holdTime: Config.Minecraft.switchHoldTime)
    }
}
