import Foundation

// MARK: - Live settings

/// Snake settings you can change while playing (sliders in the debug window).
/// Saved between launches in the app's preferences (UserDefaults).
struct SnakeSettings: Codable, Equatable {
    var pressDegrees = Config.Snake.defaultPressDegrees
    var rearmFraction = Config.Snake.defaultRearmFraction
    var holdTime = Config.Snake.defaultHoldTime
    var smoothing = Config.Snake.defaultSmoothing
    var flickSpeed = Config.Snake.defaultFlickSpeed
    var driftCorrection = Config.Snake.defaultDriftCorrection

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
        return "\(numbers), flick \(flick), auto-recenter \(driftCorrection ? "on" : "off")"
    }

    /// Keeps every value inside its slider range (e.g. after loading old saved values).
    func clamped() -> SnakeSettings {
        var copy = self
        copy.pressDegrees = Self.clamp(pressDegrees, Config.Snake.pressRange)
        copy.rearmFraction = Self.clamp(rearmFraction, Config.Snake.rearmRange)
        copy.holdTime = Self.clamp(holdTime, Config.Snake.holdRange)
        copy.smoothing = Self.clamp(smoothing, Config.Snake.smoothingRange)
        copy.flickSpeed = Self.clamp(flickSpeed, Config.Snake.flickSpeedRange)
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
}

// MARK: - One axis

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
    /// Degrees per second (signed), measured over the last couple of frames.
    private(set) var speed: Double = 0

    private var history: [(time: Double, value: Double)] = []
    private var lastFiredSign: Double = 0
    private var rearmedAt = -Double.infinity

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

    /// Feeds one frame. Returns the direction sign (+1 / −1) and whether it was a
    /// flick, if this axis fires a turn. `allowFire` = false still tracks everything
    /// but never fires (used when the other axis just fired).
    mutating func update(value: Double, at time: Double, settings: SnakeSettings,
                         allowFire: Bool) -> (sign: Double, viaFlick: Bool)? {
        self.value = value

        // Speed over the last ~2 frames (less noisy than a single frame).
        history.append((time, value))
        if history.count > 3 { history.removeFirst() }
        if let oldest = history.first, time - oldest.time > 0.001 {
            speed = (value - oldest.value) / (time - oldest.time)
        } else {
            speed = 0
        }

        // Waiting to re-arm: only this axis's value matters.
        if case .waitingForReturn(let sign) = phase {
            let distanceTowardFiredSide = sign == 0 ? abs(value) : value * sign
            if distanceTowardFiredSide < settings.rearmDegrees {
                phase = .armed
                rearmedAt = time
            }
            return nil
        }

        let sign: Double = value >= 0 ? 1 : -1
        let magnitude = abs(value)

        // Was holding but dropped back below the press threshold: cancel the hold.
        if case .holding(let holdSign, _) = phase, value * holdSign < settings.pressDegrees {
            phase = .armed
        }

        // 1. FLICK: moving fast AWAY from center, already a little way out.
        //    Fires immediately, no hold time: the speed itself shows you meant it.
        if settings.flickSpeed > 0,
           magnitude >= settings.flickMinDegrees,
           speed * sign >= settings.flickSpeed,
           !isReverseFlickBlocked(sign: sign, at: time) {
            return allowFire ? fire(sign, viaFlick: true) : nil
        }

        // 2. POSITION: past the press threshold for at least holdTime.
        guard magnitude >= settings.pressDegrees else { return nil }
        switch phase {
        case .armed:
            phase = .holding(sign: sign, since: time)
            if settings.holdTime <= 0 && allowFire { return fire(sign, viaFlick: false) }
            return nil
        case .holding(let holdSign, let since):
            if holdSign != sign {
                phase = .holding(sign: sign, since: time)
                return nil
            }
            if time - since >= settings.holdTime && allowFire { return fire(sign, viaFlick: false) }
            return nil
        case .waitingForReturn:
            return nil
        }
    }

    /// After a safety reset: wait until the head is near the center before arming.
    mutating func requireReturn() {
        phase = .waitingForReturn(sign: 0)
    }

    /// After a recenter: the head IS the center now, so arm straight away.
    mutating func arm() {
        phase = .armed
        history.removeAll()
        speed = 0
        lastFiredSign = 0
        rearmedAt = -Double.infinity
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

    private mutating func fire(_ sign: Double, viaFlick: Bool) -> (sign: Double, viaFlick: Bool) {
        phase = .waitingForReturn(sign: sign)
        lastFiredSign = sign
        return (sign, viaFlick)
    }

    private func isReverseFlickBlocked(sign: Double, at time: Double) -> Bool {
        lastFiredSign != 0 && sign == -lastFiredSign && time - rearmedAt < Config.Snake.reverseFlickBlock
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

/// Snake mode logic: two independent axes, at most one turn per frame.
struct SnakeController {
    var settings: SnakeSettings
    private(set) var horizontal = SnakeAxis(positiveName: "LEFT", negativeName: "RIGHT", axisName: "left/right")
    private(set) var vertical = SnakeAxis(positiveName: "UP", negativeName: "DOWN", axisName: "up/down")
    private var lastTurnTime = -Double.infinity

    init(settings: SnakeSettings) {
        self.settings = settings
    }

    /// Feeds one frame of head offset (your point of view). Returns a turn if one fires.
    mutating func update(offset: PlayerHeadOffset, at time: Double) -> SnakeTurn? {
        let canFire = time - lastTurnTime >= Config.Snake.minTurnInterval

        // Give the axis you're moving more a chance to fire first.
        let horizontalFirst = activity(offset.left, speed: horizontal.speed)
            >= activity(offset.up, speed: vertical.speed)

        var turn: SnakeTurn?
        if horizontalFirst {
            turn = updateHorizontal(offset.left, at: time, allowFire: canFire)
            let other = updateVertical(offset.up, at: time, allowFire: canFire && turn == nil)
            turn = turn ?? other
        } else {
            turn = updateVertical(offset.up, at: time, allowFire: canFire)
            let other = updateHorizontal(offset.left, at: time, allowFire: canFire && turn == nil)
            turn = turn ?? other
        }
        if turn != nil { lastTurnTime = time }
        return turn
    }

    mutating func requireReturn() {
        horizontal.requireReturn()
        vertical.requireReturn()
    }

    mutating func arm() {
        horizontal.arm()
        vertical.arm()
    }

    var isHolding: Bool {
        if case .holding = horizontal.phase { return true }
        if case .holding = vertical.phase { return true }
        return false
    }

    /// How "active" an axis is, compared with what it takes to fire.
    private func activity(_ value: Double, speed: Double) -> Double {
        let byPosition = abs(value) / max(settings.pressDegrees, 0.1)
        let bySpeed = settings.flickSpeed > 0 ? abs(speed) / settings.flickSpeed : 0
        return max(byPosition, bySpeed)
    }

    private mutating func updateHorizontal(_ value: Double, at time: Double, allowFire: Bool) -> SnakeTurn? {
        guard let fired = horizontal.update(value: value, at: time, settings: settings, allowFire: allowFire) else {
            return nil
        }
        return SnakeTurn(gesture: fired.sign > 0 ? .turnLeft : .turnRight,
                         viaFlick: fired.viaFlick,
                         speed: abs(horizontal.speed))
    }

    private mutating func updateVertical(_ value: Double, at time: Double, allowFire: Bool) -> SnakeTurn? {
        guard let fired = vertical.update(value: value, at: time, settings: settings, allowFire: allowFire) else {
            return nil
        }
        return SnakeTurn(gesture: fired.sign > 0 ? .tiltUp : .tiltDown,
                         viaFlick: fired.viaFlick,
                         speed: abs(vertical.speed))
    }
}
