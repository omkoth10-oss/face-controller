import Foundation

/// What the aiming is doing right now (for the debug window).
struct AimState: Equatable {
    var active = false
    /// Pointer speed in screen points per second, from YOUR point of view
    /// (+x = right, +y = up).
    var speedX: Double = 0
    var speedY: Double = 0
    var inDeadzoneX = true
    var inDeadzoneY = true
    var sensitivity = Config.Aim.defaultSensitivity
}

/// Head-to-mouse aiming. The head works like a joystick:
///
///   offset from neutral ──▶ deadzone ──▶ response curve ──▶ speed ──▶ mouse moves
///
/// - DEADZONE: small wobbles near neutral do nothing, so the pointer doesn't drift.
/// - RESPONSE CURVE: just past the deadzone the pointer moves slowly (precise aim);
///   further out it speeds up, reaching full speed at the "full speed angle".
///   speed = maxSpeed × t^exponent, where t goes 0 → 1 between deadzone and full-speed angle.
/// - SENSITIVITY: one multiplier on top (the slider in the debug window).
///
/// Why a separate timer: the camera only gives us 30–60 head readings a second.
/// Moving the mouse only that often looks steppy, so a 120 Hz timer on its own
/// queue moves the pointer in small steps at the latest speed. The tracking loop
/// only sets the target speed; it never waits for the mouse.
final class AimController {

    private let input: VirtualInput
    private let queue = DispatchQueue(label: "FaceController.aim", qos: .userInteractive)

    // Shared between the tracking queue (writes) and the aim queue (reads): use `lock`.
    private let lock = NSLock()
    private var targetX = 0.0          // screen points/s, +x = right
    private var targetY = 0.0          // screen points/s, +y = DOWN (screen coordinates)
    private var lastTargetTime = 0.0
    private var sensitivity = Config.Aim.defaultSensitivity

    // Only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var currentX = 0.0
    private var currentY = 0.0
    private var remainderX = 0.0       // Sub-point movement carried to the next step.
    private var remainderY = 0.0
    private var lastTick: Double?

    init(input: VirtualInput) {
        self.input = input
    }

    // MARK: - Control (any thread)

    /// Starts or stops the 120 Hz mouse timer (only runs in Aim mode).
    func setActive(_ active: Bool) {
        stopMoving()
        queue.async {
            if active {
                guard self.timer == nil else { return }
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(),
                               repeating: 1.0 / Config.Aim.outputRate,
                               leeway: .microseconds(500))
                timer.setEventHandler { [weak self] in self?.tick() }
                timer.resume()
                self.timer = timer
            } else {
                self.timer?.cancel()
                self.timer = nil
            }
            self.resetMotion()
        }
    }

    func setSensitivity(_ value: Double) {
        lock.lock()
        sensitivity = min(max(value, Config.Aim.sensitivityRange.lowerBound), Config.Aim.sensitivityRange.upperBound)
        lock.unlock()
    }

    /// Stops the pointer immediately (face lost, control off, mode change...).
    func stopMoving() {
        lock.lock()
        targetX = 0
        targetY = 0
        lock.unlock()
    }

    /// Called by the tracking loop every frame with your head offset.
    /// Returns what the aiming is doing, for the debug window.
    func update(offset: PlayerHeadOffset, at time: Double) -> AimState {
        lock.lock()
        let sensitivity = self.sensitivity
        lock.unlock()

        // Positive "left" means YOUR left, so the pointer moves left (-x on screen).
        // Positive "up" means chin up, so the pointer moves up (-y on screen).
        let speedRight = -Self.speed(for: offset.left,
                                     deadzone: Config.Aim.horizontalDeadzone,
                                     fullSpeedAngle: Config.Aim.horizontalFullSpeedAngle,
                                     maxSpeed: Config.Aim.maxSpeedX) * sensitivity
        let speedUp = Self.speed(for: offset.up,
                                 deadzone: Config.Aim.verticalDeadzone,
                                 fullSpeedAngle: Config.Aim.verticalFullSpeedAngle,
                                 maxSpeed: Config.Aim.maxSpeedY) * sensitivity

        lock.lock()
        targetX = speedRight
        targetY = -speedUp  // Screen y grows downward.
        lastTargetTime = time
        lock.unlock()

        return AimState(active: true,
                        speedX: speedRight,
                        speedY: speedUp,
                        inDeadzoneX: abs(offset.left) <= Config.Aim.horizontalDeadzone,
                        inDeadzoneY: abs(offset.up) <= Config.Aim.verticalDeadzone,
                        sensitivity: sensitivity)
    }

    var currentSensitivity: Double {
        lock.lock()
        defer { lock.unlock() }
        return sensitivity
    }

    // MARK: - The response curve

    /// Degrees past neutral → points per second (sign kept).
    static func speed(for angle: Double, deadzone: Double, fullSpeedAngle: Double, maxSpeed: Double) -> Double {
        let magnitude = abs(angle)
        guard magnitude > deadzone else { return 0 }
        let span = max(fullSpeedAngle - deadzone, 0.1)
        let t = min(1, (magnitude - deadzone) / span)   // 0 at the deadzone edge, 1 at full speed.
        let speed = maxSpeed * pow(t, Config.Aim.curveExponent)
        return angle < 0 ? -speed : speed
    }

    // MARK: - The 120 Hz mouse timer (runs on `queue`)

    private func tick() {
        let now = HostClock.now()
        lock.lock()
        var wantX = targetX
        var wantY = targetY
        let isStale = now - lastTargetTime > Config.Aim.staleAfter
        lock.unlock()

        // Safety: no fresh head data (camera stalled, face lost) -> stop.
        if isStale {
            wantX = 0
            wantY = 0
        }

        let dt = min(max(now - (lastTick ?? now), 0), 0.05)
        lastTick = now

        // Ease toward the target speed (light smoothing). Stopping is instant.
        let blend = Config.Aim.smoothingTime > 0 ? min(1, dt / Config.Aim.smoothingTime) : 1
        currentX = wantX == 0 ? 0 : currentX + (wantX - currentX) * blend
        currentY = wantY == 0 ? 0 : currentY + (wantY - currentY) * blend
        if currentX == 0 { remainderX = 0 }
        if currentY == 0 { remainderY = 0 }

        // Move by whole points; keep the leftover fraction for the next tick so slow
        // movements still add up instead of rounding away to nothing.
        remainderX += currentX * dt
        remainderY += currentY * dt
        let stepX = Int(remainderX.rounded(.towardZero))
        let stepY = Int(remainderY.rounded(.towardZero))
        remainderX -= Double(stepX)
        remainderY -= Double(stepY)

        if stepX != 0 || stepY != 0 {
            input.moveMouse(dx: stepX, dy: stepY)
        }
    }

    private func resetMotion() {
        currentX = 0
        currentY = 0
        remainderX = 0
        remainderY = 0
        lastTick = nil
    }
}
