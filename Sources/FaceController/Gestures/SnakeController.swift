import Foundation

// MARK: - Live settings

/// Snake settings you can change while playing (sliders in the debug window).
/// Saved between launches in the app's preferences (UserDefaults).
/// (The old "auto-recenter" switch moved to the Floating center settings.)
struct SnakeSettings: Codable, Equatable {
    var pressDegrees = Config.Snake.defaultPressDegrees
    var rearmFraction = Config.Snake.defaultRearmFraction
    var holdTime = Config.Snake.defaultHoldTime
    var smoothing = Config.Snake.defaultSmoothing
    var flickSpeed = Config.Snake.defaultFlickSpeed
    var minTurnInterval = Config.Snake.defaultMinTurnInterval
    /// Optional safety blocks (off by default, switches in the Snake panel).
    var bounceBlockEnabled = Config.Snake.defaultBounceBlockEnabled
    var sameDirectionBlockEnabled = Config.Snake.defaultSameDirectionBlockEnabled

    enum CodingKeys: String, CodingKey {
        case pressDegrees, rearmFraction, holdTime, smoothing, flickSpeed
        case minTurnInterval, bounceBlockEnabled, sameDirectionBlockEnabled
    }

    /// Degrees below which an axis re-arms after a turn.
    var rearmDegrees: Double { pressDegrees * rearmFraction }
    /// A flick only counts once the head is at least this far from center.
    var flickMinDegrees: Double { pressDegrees * Config.Snake.flickMinFraction }

    /// Smoothing amount (0...1) → One Euro filter cutoff in Hz; nil = smoothing off.
    /// 0 → off, small → ~20 Hz (almost no lag), 1 → 1 Hz (heavy, laggy).
    var smoothingCutoff: Double? {
        guard smoothing > 0.001 else { return nil }
        return 20 * pow(1.0 / 20.0, smoothing)
    }

    /// Rough delay the smoothing adds while the head is still (ms). Less while moving.
    var smoothingLagMs: Double {
        smoothingCutoff.map { 1000 / (2 * Double.pi * $0) } ?? 0
    }

    /// One line to copy and report back.
    var summary: String {
        let numbers = String(format: "press %.1f°, re-arm %.0f%%, hold %.0f ms, smoothing %.0f%%",
                             pressDegrees, rearmFraction * 100, holdTime * 1000, smoothing * 100)
        let flick = flickSpeed > 0 ? String(format: "%.0f°/s", flickSpeed) : "off"
        let spacing = String(format: "%.0f ms", minTurnInterval * 1000)
        return "\(numbers), flick \(flick), min gap \(spacing), bounce block \(bounceBlockEnabled ? "on" : "off"), double-turn block \(sameDirectionBlockEnabled ? "on" : "off")"
    }

    /// Keeps every value inside its slider range (e.g. after loading old saved values).
    func clamped() -> SnakeSettings {
        var copy = self
        copy.pressDegrees = Self.clamp(pressDegrees, Config.Snake.pressRange)
        copy.rearmFraction = Self.clamp(rearmFraction, Config.Snake.rearmRange)
        copy.holdTime = Self.clamp(holdTime, Config.Snake.holdRange)
        copy.smoothing = Self.clamp(smoothing, Config.Snake.smoothingRange)
        copy.flickSpeed = Self.clamp(flickSpeed, Config.Snake.flickSpeedRange)
        copy.minTurnInterval = Self.clamp(minTurnInterval, Config.Snake.minTurnIntervalRange)
        return copy
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Saving

    private static let storageKey = "snakeSettings.v1"

    static func load() -> SnakeSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(SnakeSettings.self, from: data) else {
            return SnakeSettings()
        }
        return saved.clamped()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// The old Snake "auto-recenter" switch from the previous version, if it was saved.
    /// Used once, to carry your choice over to the new Floating center setting.
    static func legacyDriftCorrection() -> Bool? {
        struct Legacy: Decodable { let driftCorrection: Bool? }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        return legacy.driftCorrection
    }
}

extension SnakeSettings {
    /// Reads saved values, filling in defaults for anything missing (and ignoring
    /// old keys), so your saved slider values keep working across app updates.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SnakeSettings()
        pressDegrees = try container.decodeIfPresent(Double.self, forKey: .pressDegrees) ?? defaults.pressDegrees
        rearmFraction = try container.decodeIfPresent(Double.self, forKey: .rearmFraction) ?? defaults.rearmFraction
        holdTime = try container.decodeIfPresent(Double.self, forKey: .holdTime) ?? defaults.holdTime
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? defaults.smoothing
        flickSpeed = try container.decodeIfPresent(Double.self, forKey: .flickSpeed) ?? defaults.flickSpeed
        minTurnInterval = try container.decodeIfPresent(Double.self, forKey: .minTurnInterval) ?? defaults.minTurnInterval
        bounceBlockEnabled = try container.decodeIfPresent(Bool.self, forKey: .bounceBlockEnabled)
            ?? defaults.bounceBlockEnabled
        sameDirectionBlockEnabled = try container.decodeIfPresent(Bool.self, forKey: .sameDirectionBlockEnabled)
            ?? defaults.sameDirectionBlockEnabled
    }
}

// MARK: - One axis

/// What one axis did this frame.
enum SnakeAxisResult {
    /// A turn fired (sign +1 = left/up, −1 = right/down).
    case fired(sign: Double, viaFlick: Bool)
    /// A turn WANTED to fire but was held back, and why (shown in the Turn log).
    case blocked(sign: Double, reason: String)
}

/// One axis of Snake mode: left/right OR up/down.
///
/// The value is signed from YOUR point of view (+ = left or up, − = right or down).
/// Each axis has its own little state machine:
///
///   armed ──(flick, or past press threshold for holdTime)──▶ TURN ──▶ waiting for return
///     ▲                                                                   │
///     └────────── back below the re-arm level on THIS axis ───────────────┘
///
/// Because the two axes are independent, you can chain "left" then "up" without
/// first bringing your head all the way back to the center.
///
/// Two OPTIONAL safety blocks (off by default; Google Snake ignores 180° reversals
/// and repeated directions itself, so they mostly ate real fast turns):
/// - BOUNCE-BACK: just after re-arming, a turn the OPPOSITE way on this axis is
///   ignored for a moment (your head swinging back past the center).
/// - DOUBLE TURN: the same direction can't fire twice in quick succession.
struct SnakeAxis {
    enum Phase: Equatable {
        case armed
        /// Past the press threshold, waiting out the hold time.
        case holding(sign: Double, since: Double)
        /// Fired toward `sign`; waiting for the head to come back. sign 0 = "come back
        /// near the center first" (after calibration, face lost, etc.).
        case waitingForReturn(sign: Double)
    }

    let positiveName: String   // "LEFT" or "UP"
    let negativeName: String   // "RIGHT" or "DOWN"
    let axisName: String       // "left/right" or "up/down"

    private(set) var phase: Phase = .waitingForReturn(sign: 0)
    private(set) var value: Double = 0
    /// Degrees per second (signed), averaged over the last two frames (for display).
    private(set) var speed: Double = 0

    private var history: [(time: Double, value: Double)] = []
    /// Speed over just the latest frame, and over the frame before it.
    private var latestStepSpeed: Double = 0
    private var previousStepSpeed: Double = 0

    private var lastFiredSign: Double = 0
    private var lastFiredAt = -Double.infinity
    private var rearmedAt = -Double.infinity
    /// Set once a blocked attempt has been reported, so one attempt = one log line.
    private var reportedBlock = false

    init(positiveName: String, negativeName: String, axisName: String) {
        self.positiveName = positiveName
        self.negativeName = negativeName
        self.axisName = axisName
    }

    func name(for sign: Double) -> String { sign > 0 ? positiveName : negativeName }

    var isArmed: Bool {
        if case .waitingForReturn = phase { return false }
        return true
    }

    var isHolding: Bool {
        if case .holding = phase { return true }
        return false
    }

    /// Feeds one frame. Returns a fired or blocked turn, or nil.
    mutating func update(value: Double, at time: Double, settings: SnakeSettings) -> SnakeAxisResult? {
        self.value = value
        updateSpeeds(value: value, time: time)

        // Waiting to re-arm: only this axis's value matters.
        if case .waitingForReturn(let sign) = phase {
            let distanceTowardFiredSide = sign == 0 ? abs(value) : value * sign
            if distanceTowardFiredSide < settings.rearmDegrees {
                phase = .armed
                rearmedAt = time
                reportedBlock = false
                return nil
            }
            // Flicking the same way AGAIN without coming back first: report it once,
            // because "it didn't turn" is confusing otherwise. (Ignore the first moment
            // after a turn: the head is usually still finishing that same movement.)
            if sign != 0, time - lastFiredAt > Config.Snake.sameDirectionCooldown,
               isFlick(toward: sign, settings: settings), !reportedBlock {
                reportedBlock = true
                return .blocked(sign: sign, reason: String(
                    format: "not re-armed yet (%@ still at %.1f°, needs < %.1f°)",
                    axisName as NSString, value * sign, settings.rearmDegrees))
            }
            return nil
        }

        let sign: Double = value >= 0 ? 1 : -1
        let magnitude = abs(value)

        // Head has settled: a new attempt may be reported again.
        if magnitude < settings.flickMinDegrees && abs(speed) < settings.flickSpeed / 2 {
            reportedBlock = false
        }

        // Was holding but dropped back below the press threshold: cancel the hold.
        if case .holding(let holdSign, _) = phase, value * holdSign < settings.pressDegrees {
            phase = .armed
        }

        // Does this frame WANT a turn, and how?
        var wantsTurn = false
        var viaFlick = false
        if settings.flickSpeed > 0, magnitude >= settings.flickMinDegrees,
           isFlick(toward: sign, settings: settings) {
            // 1. FLICK: moving fast AWAY from center. No hold time: the speed shows you meant it.
            wantsTurn = true
            viaFlick = true
        } else if magnitude >= settings.pressDegrees {
            // 2. POSITION: past the press threshold for at least holdTime.
            switch phase {
            case .armed:
                phase = .holding(sign: sign, since: time)
                wantsTurn = settings.holdTime <= 0
            case .holding(let holdSign, let since):
                if holdSign != sign {
                    phase = .holding(sign: sign, since: time)
                } else {
                    wantsTurn = time - since >= settings.holdTime
                }
            case .waitingForReturn:
                break
            }
        }
        guard wantsTurn else { return nil }

        // Held back? Report it once per attempt; it may still fire once the block ends.
        if let reason = blockReason(sign: sign, at: time, settings: settings) {
            if reportedBlock { return nil }
            reportedBlock = true
            return .blocked(sign: sign, reason: reason)
        }

        phase = .waitingForReturn(sign: sign)
        lastFiredSign = sign
        lastFiredAt = time
        reportedBlock = false
        return .fired(sign: sign, viaFlick: viaFlick)
    }

    /// After a safety reset: wait until the head is near the center before arming.
    mutating func requireReturn() {
        phase = .waitingForReturn(sign: 0)
        reportedBlock = false
    }

    /// After a recenter: the head IS the center now, so arm straight away.
    mutating func arm() {
        phase = .armed
        history.removeAll()
        speed = 0
        latestStepSpeed = 0
        previousStepSpeed = 0
        lastFiredSign = 0
        lastFiredAt = -Double.infinity
        rearmedAt = -Double.infinity
        reportedBlock = false
    }

    /// Plain-language state for the debug window, e.g. why it isn't firing.
    func statusText(settings: SnakeSettings) -> String {
        let rearm = String(format: "%.1f°", settings.rearmDegrees)
        switch phase {
        case .armed:
            var text = "ready: \(axisName) at \(String(format: "%+.1f°", value)), fires at ±\(String(format: "%.1f°", settings.pressDegrees))"
            if settings.flickSpeed > 0 {
                text += " or a flick ≥ \(String(format: "%.0f°/s", settings.flickSpeed))"
            }
            return text
        case .holding(let sign, _):
            return "holding \(name(for: sign)) (\(String(format: "%+.1f°", value)))…"
        case .waitingForReturn(let sign):
            if sign == 0 {
                return "waiting: \(axisName) at \(String(format: "%.1f°", abs(value))), needs < \(rearm) to arm"
            }
            return "waiting: \(axisName) still at \(String(format: "%.1f°", value * sign)) toward \(name(for: sign)), needs < \(rearm) to re-arm"
        }
    }

    // MARK: Private

    private mutating func updateSpeeds(value: Double, time: Double) {
        history.append((time, value))
        if history.count > 3 { history.removeFirst() }
        let count = history.count
        func stepSpeed(_ a: (time: Double, value: Double), _ b: (time: Double, value: Double)) -> Double {
            let dt = b.time - a.time
            return dt > 0.001 ? (b.value - a.value) / dt : 0
        }
        latestStepSpeed = count >= 2 ? stepSpeed(history[count - 2], history[count - 1]) : 0
        previousStepSpeed = count >= 3 ? stepSpeed(history[count - 3], history[count - 2]) : 0
        speed = count >= 2 ? stepSpeed(history[0], history[count - 1]) : 0
    }

    /// Is the head flicking AWAY from center toward `sign`?
    /// Fires on the two-frame average, OR one frame EARLIER when the latest frame is
    /// already fast and the frame before was moving the same way (motion onset).
    private func isFlick(toward sign: Double, settings: SnakeSettings) -> Bool {
        guard settings.flickSpeed > 0 else { return false }
        let byAverage = speed * sign >= settings.flickSpeed
        let byOnset = latestStepSpeed * sign >= settings.flickSpeed
            && previousStepSpeed * sign >= settings.flickSpeed * Config.Snake.flickOnsetFraction
        return byAverage || byOnset
    }

    /// Optional bounce-back and double-turn protection for this axis.
    private func blockReason(sign: Double, at time: Double, settings: SnakeSettings) -> String? {
        if settings.bounceBlockEnabled, lastFiredSign != 0, sign == -lastFiredSign,
           time - rearmedAt < Config.Snake.bounceBlock {
            return String(format: "bounce-back block: opposite of %@ within %.0f ms of re-arming",
                          name(for: lastFiredSign) as NSString, Config.Snake.bounceBlock * 1000)
        }
        if settings.sameDirectionBlockEnabled, lastFiredSign != 0, sign == lastFiredSign,
           time - lastFiredAt < Config.Snake.sameDirectionCooldown {
            return String(format: "double-turn block: same direction within %.0f ms",
                          Config.Snake.sameDirectionCooldown * 1000)
        }
        return nil
    }
}

// MARK: - Both axes together

/// A Snake turn that just fired.
struct SnakeTurn {
    let gesture: GestureID   // .turnLeft, .turnRight, .tiltUp or .tiltDown
    let viaFlick: Bool
    /// Head speed when it fired (degrees per second).
    let speed: Double
}

/// A turn that wanted to fire but was held back.
struct SnakeBlockedTurn {
    let gesture: GestureID
    let reason: String
}

/// What Snake did this frame.
struct SnakeFrameResult {
    /// Turns that fired this frame, most active direction first. Usually 0 or 1;
    /// 2 when you move diagonally (e.g. left and up at once): BOTH are sent.
    var turns: [SnakeTurn] = []
    var blocked: [SnakeBlockedTurn] = []
}

/// Snake mode logic: two independent axes. Both may fire in the same frame; the
/// engine spaces the key taps apart (min time between turns), it never drops one.
struct SnakeController {
    var settings: SnakeSettings
    private(set) var horizontal = SnakeAxis(positiveName: "LEFT", negativeName: "RIGHT", axisName: "left/right")
    private(set) var vertical = SnakeAxis(positiveName: "UP", negativeName: "DOWN", axisName: "up/down")

    init(settings: SnakeSettings) {
        self.settings = settings
    }

    /// Feeds one frame of head offset (your point of view).
    mutating func update(offset: PlayerHeadOffset, at time: Double) -> SnakeFrameResult {
        // The axis you're moving more goes first (its tap is sent first).
        let horizontalFirst = activity(offset.left, speed: horizontal.speed)
            >= activity(offset.up, speed: vertical.speed)

        var result = SnakeFrameResult()
        if horizontalFirst {
            handle(updateHorizontal(offset.left, at: time), into: &result)
            handle(updateVertical(offset.up, at: time), into: &result)
        } else {
            handle(updateVertical(offset.up, at: time), into: &result)
            handle(updateHorizontal(offset.left, at: time), into: &result)
        }
        return result
    }

    mutating func requireReturn() {
        horizontal.requireReturn()
        vertical.requireReturn()
    }

    mutating func arm() {
        horizontal.arm()
        vertical.arm()
    }

    var isHolding: Bool { horizontal.isHolding || vertical.isHolding }
    var bothArmed: Bool { horizontal.isArmed && vertical.isArmed }

    static func name(of gesture: GestureID) -> String {
        switch gesture {
        case .turnLeft: return "LEFT"
        case .turnRight: return "RIGHT"
        case .tiltUp: return "UP"
        case .tiltDown: return "DOWN"
        case .mouthOpen, .eyebrowsRaise: return gesture.displayName
        }
    }

    // MARK: Private

    private enum Axis { case horizontal, vertical }

    /// How "active" an axis is, compared with what it takes to fire.
    private func activity(_ value: Double, speed: Double) -> Double {
        let byPosition = abs(value) / max(settings.pressDegrees, 0.1)
        let bySpeed = settings.flickSpeed > 0 ? abs(speed) / settings.flickSpeed : 0
        return max(byPosition, bySpeed)
    }

    private mutating func updateHorizontal(_ value: Double, at time: Double) -> (SnakeAxisResult, Axis, Double)? {
        guard let result = horizontal.update(value: value, at: time, settings: settings) else {
            return nil
        }
        return (result, .horizontal, abs(horizontal.speed))
    }

    private mutating func updateVertical(_ value: Double, at time: Double) -> (SnakeAxisResult, Axis, Double)? {
        guard let result = vertical.update(value: value, at: time, settings: settings) else {
            return nil
        }
        return (result, .vertical, abs(vertical.speed))
    }

    private func handle(_ update: (SnakeAxisResult, Axis, Double)?, into result: inout SnakeFrameResult) {
        guard let update = update else { return }
        let (axisResult, axis, speed) = update
        switch axisResult {
        case .fired(let sign, let viaFlick):
            result.turns.append(SnakeTurn(gesture: Self.gesture(axis: axis, sign: sign), viaFlick: viaFlick, speed: speed))
        case .blocked(let sign, let reason):
            result.blocked.append(SnakeBlockedTurn(gesture: Self.gesture(axis: axis, sign: sign), reason: reason))
        }
    }

    private static func gesture(axis: Axis, sign: Double) -> GestureID {
        switch axis {
        case .horizontal: return sign > 0 ? .turnLeft : .turnRight
        case .vertical: return sign > 0 ? .tiltUp : .tiltDown
        }
    }
}
