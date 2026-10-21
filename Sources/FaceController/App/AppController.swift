import AppKit
import Combine  // ObservableObject / @Published
import Foundation

/// Everything the debug window displays. Updated on the main thread only.
final class DebugModel: ObservableObject {
    @Published var engine = EngineSnapshot()
    @Published var controlEnabled = Config.Safety.startWithControlOn
    @Published var cameraPermission: CameraPermission = .notDetermined
    @Published var accessibilityGranted = true
    @Published var cameraInfo: CameraInfo?
    @Published var cameraStarting = false
    @Published var cameraError: String?
    @Published var killSwitchRegistered = false
    @Published var mode = Config.Mapping.startMode
    @Published var aimSensitivity = Config.Aim.defaultSensitivity
    /// Your Snake slider values (loaded from the last launch).
    @Published var snakeSettings = SnakeSettings.load()
    /// Floating center on/off per mode + follow time (loaded from the last launch).
    @Published var floatingCenterSettings = FloatingCenterSettings.load()
    /// Minecraft preset: head option and its sliders (loaded from the last launch).
    @Published var minecraftSettings = MinecraftSettings.load()
    /// Scroll mode: option, sliders, switches (loaded from the last launch).
    @Published var scrollSettings = ScrollSettings.load()
    /// Scroll mode's Shorts flick sliders (same kind as Snake's, saved separately).
    @Published var shortsSettings = SnakeSettings.loadShorts()
    @Published var recenterHotKeyRegistered = false
}

/// Wires all the pieces together and handles everything that happens on the
/// main thread: permissions, the kill switch, the window's buttons, quitting.
///
///     Camera ──frames──▶ ControlEngine (tracking queue) ──keys/clicks──▶ VirtualInput ──▶ macOS
///                               │   └──head offset──▶ AimController ──mouse──┘  ▲
///                          snapshots                (120 Hz, Aim mode)           │
///                               ▼                                 kill switch / permissions
///                          DebugModel ──▶ DebugView        AppController (main thread)
///
/// Use this class from the main thread only.
final class AppController {
    let model = DebugModel()
    let input: VirtualInput
    let aim: AimController
    let scroller: ScrollController
    let engine: ControlEngine
    let camera: CameraManager

    private var killSwitch: GlobalHotKey?
    private var recenterHotKey: GlobalHotKey?
    /// The MOVE / AIM label over the game (created the first time it's needed).
    private var overlay: GameOverlay?
    private var permissionTimer: Timer?
    private var controlEnabled = Config.Safety.startWithControlOn
    private var cameraStartRequested = false
    private var cameraAccessRequested = false
    private var accessibilityPrompted = false
    private var lastAccessibilityState: Bool?

    init() {
        let input = VirtualInput()
        let aim = AimController(input: input)
        let scroller = ScrollController(input: input)
        let engine = ControlEngine(input: input, aim: aim, scroller: scroller)
        self.input = input
        self.aim = aim
        self.scroller = scroller
        self.engine = engine
        // Frames go straight from the camera to the engine, on the engine's queue.
        self.camera = CameraManager(frameQueue: engine.queue,
                                    onFrame: { [weak engine] buffer in engine?.process(buffer) },
                                    onDroppedFrame: { [weak engine] in engine?.frameDropped() })
    }

    // MARK: - Lifecycle

    func start() {
        // Safety first: make sure keys are released however the app exits.
        ExitGuard.install(input: input)
        input.setBlocked(.controlOff, !controlEnabled)
        model.controlEnabled = controlEnabled

        engine.onSnapshot = { [weak self] snapshot in
            // Called on the tracking queue; the window must be updated on the main thread.
            DispatchQueue.main.async {
                self?.model.engine = snapshot
            }
        }
        engine.onHeadJobSwitch = { job in
            // Called on the tracking queue. A different sound for each job, so you
            // know which one you're in without looking.
            DispatchQueue.main.async {
                NSSound(named: job == .move ? Config.Minecraft.moveSound : Config.Minecraft.aimSound)?.play()
            }
        }
        engine.setSnakeSettings(model.snakeSettings)
        engine.setFloatingCenterSettings(model.floatingCenterSettings)
        engine.setMinecraftSettings(model.minecraftSettings)
        engine.setScrollSettings(model.scrollSettings)
        engine.setShortsSettings(model.shortsSettings)
        engine.start()
        updateOverlay()

        registerKillSwitch()
        registerRecenterHotKey()

        checkPermissions()
        let timer = Timer(timeInterval: Config.Safety.permissionCheckInterval, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
        // `.common` keeps the timer running even while you drag the window or use a menu.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    /// Called when the app quits.
    func shutdown() {
        ExitGuard.releaseEverything()  // Release keys FIRST, before anything else.
        permissionTimer?.invalidate()
        permissionTimer = nil
        overlay?.setVisible(false)
        killSwitch = nil
        recenterHotKey = nil
        // The camera is closed automatically when the process exits. We don't wait
        // for it to stop here: waiting on the main thread while quitting could hang.
    }

    // MARK: - Control on/off (kill switch)

    func toggleControl() {
        setControl(enabled: !controlEnabled)
    }

    func setControl(enabled: Bool) {
        controlEnabled = enabled
        // This releases everything held immediately (right here on the main thread),
        // without waiting for the tracking loop. It also stops the mouse.
        input.setBlocked(.controlOff, !enabled)
        aim.stopMoving()
        scroller.stopMoving()
        engine.controlWasToggled(isOn: enabled)
        model.controlEnabled = enabled
        // An audible cue, so you know the state even inside a full-screen game.
        NSSound(named: enabled ? "Tink" : "Pop")?.play()
    }

    func recalibrate() {
        engine.recalibrate()
    }

    /// Keys / Aim / Snake / Minecraft / Scroll. Releases everything immediately, then switches.
    func setMode(_ mode: ControlMode) {
        guard mode != model.mode else { return }
        model.mode = mode
        input.releaseAll()
        aim.stopMoving()
        scroller.stopMoving()
        engine.setMode(mode)
        updateOverlay()
    }

    func setAimSensitivity(_ value: Double) {
        model.aimSensitivity = value
        aim.setSensitivity(value)
    }

    /// Instantly makes the current head position the new neutral (button, R key, ⌃⌥⌘R).
    func recenter() {
        engine.recenter()
        NSSound(named: "Morse")?.play()
    }

    /// New Snake slider values: used immediately and saved for next time.
    func setSnakeSettings(_ settings: SnakeSettings) {
        let clamped = settings.clamped()
        guard clamped != model.snakeSettings else { return }
        model.snakeSettings = clamped
        clamped.save()
        engine.setSnakeSettings(clamped)
    }

    func resetSnakeSettings() {
        setSnakeSettings(SnakeSettings())
    }

    /// Floating center changes (per-mode switch, follow time): used now and saved.
    func setFloatingCenterSettings(_ settings: FloatingCenterSettings) {
        let clamped = settings.clamped()
        guard clamped != model.floatingCenterSettings else { return }
        model.floatingCenterSettings = clamped
        clamped.save()
        engine.setFloatingCenterSettings(clamped)
    }

    /// Scroll mode changes (option, sliders, switches): used now and saved.
    func setScrollSettings(_ settings: ScrollSettings) {
        let clamped = settings.clamped()
        guard clamped != model.scrollSettings else { return }
        model.scrollSettings = clamped
        clamped.save()
        engine.setScrollSettings(clamped)
    }

    func resetScrollSettings() {
        setScrollSettings(ScrollSettings())
        setShortsSettings(SnakeSettings.shortsDefaults)
    }

    /// New Shorts flick slider values: used immediately and saved for next time.
    func setShortsSettings(_ settings: SnakeSettings) {
        let clamped = settings.clamped()
        guard clamped != model.shortsSettings else { return }
        model.shortsSettings = clamped
        clamped.saveShorts()
        engine.setShortsSettings(clamped)
    }

    /// Minecraft preset changes (head option, sliders, overlay): used now and saved.
    func setMinecraftSettings(_ settings: MinecraftSettings) {
        let clamped = settings.clamped()
        guard clamped != model.minecraftSettings else { return }
        model.minecraftSettings = clamped
        clamped.save()
        engine.setMinecraftSettings(clamped)
        updateOverlay()
    }

    func resetMinecraftSettings() {
        setMinecraftSettings(MinecraftSettings())
    }

    /// Option 2's "Switch now" button (the engine plays the sound).
    func toggleHeadJob() {
        engine.toggleHeadJob()
    }

    /// The overlay shows in the Minecraft preset, unless switched off.
    private func updateOverlay() {
        let show = model.mode == .minecraft && model.minecraftSettings.overlayEnabled
        if show && overlay == nil {
            overlay = GameOverlay(model: model)
        }
        overlay?.setVisible(show)
    }

    private func registerKillSwitch() {
        killSwitch = GlobalHotKey(keyCode: Config.Safety.killSwitchKeyCode,
                                  modifiers: Config.Safety.killSwitchModifiers) { [weak self] in
            self?.toggleControl()
        }
        model.killSwitchRegistered = (killSwitch != nil)
        if killSwitch == nil {
            engine.noteEvent("WARNING: couldn't register the kill-switch hotkey (another app may use it)")
        }
    }

    private func registerRecenterHotKey() {
        recenterHotKey = GlobalHotKey(keyCode: Config.Recenter.keyCode,
                                      modifiers: Config.Recenter.modifiers,
                                      id: 2) { [weak self] in
            self?.recenter()
        }
        model.recenterHotKeyRegistered = (recenterHotKey != nil)
        if recenterHotKey == nil {
            engine.noteEvent("WARNING: couldn't register the recenter hotkey (another app may use it)")
        }
    }

    // MARK: - Camera

    func retryCamera() {
        cameraStartRequested = false
        startCameraIfNeeded()
    }

    private func startCameraIfNeeded() {
        guard !cameraStartRequested else { return }
        cameraStartRequested = true
        model.cameraStarting = true
        model.cameraError = nil

        camera.start { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.model.cameraStarting = false
                switch result {
                case .success(let info):
                    self.model.cameraInfo = info
                    self.model.cameraError = nil
                    self.engine.setFramesMirrored(info.framesMirrored)
                case .failure(let error):
                    self.model.cameraError = error.message
                    self.cameraStartRequested = false  // Allow "Retry camera".
                    self.engine.noteEvent("Camera error: \(error.message)")
                }
            }
        }
    }

    // MARK: - Permissions

    /// Runs at startup and then every `permissionCheckInterval` seconds.
    private func checkPermissions() {
        // Camera
        let cameraStatus = Permissions.cameraStatus()
        if model.cameraPermission != cameraStatus {
            model.cameraPermission = cameraStatus
        }
        switch cameraStatus {
        case .authorized:
            if model.cameraInfo == nil && model.cameraError == nil {
                startCameraIfNeeded()
            }
        case .notDetermined:
            if !cameraAccessRequested {
                cameraAccessRequested = true
                Permissions.requestCameraAccess { [weak self] _ in
                    DispatchQueue.main.async { self?.checkPermissions() }
                }
            }
        case .denied, .restricted:
            break  // The window shows instructions.
        }

        // Accessibility (needed to send key presses)
        let accessibilityOK = Permissions.accessibilityGranted()
        if !accessibilityOK && !accessibilityPrompted {
            accessibilityPrompted = true
            Permissions.promptForAccessibility()
        }
        // Without permission macOS silently drops our events, so block input.
        // If permission is REMOVED while running, this also releases everything held.
        input.setBlocked(.noAccessibilityPermission, !accessibilityOK)
        if lastAccessibilityState == true && !accessibilityOK {
            engine.noteEvent("Accessibility permission was turned off: everything released")
        } else if lastAccessibilityState == false && accessibilityOK {
            engine.noteEvent("Accessibility permission granted")
        }
        lastAccessibilityState = accessibilityOK
        if model.accessibilityGranted != accessibilityOK {
            model.accessibilityGranted = accessibilityOK
        }
    }
}
