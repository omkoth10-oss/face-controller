# Face Controller

A free Mac app that turns your webcam into a game controller using head and face
gestures. It sends real keyboard input at the system level, so it works with
almost any game.

> **Status: Phase 2 prototype.** Head gestures (tilt up, turn left/right),
> facial expressions (open mouth, raise eyebrows), head-to-mouse aiming, and a
> Snake mode for Google Snake. A debug window shows exactly what the tracker sees,
> every gesture's live value, how close you are to triggering, and how fast
> everything is.

## Requirements

- An **Apple Silicon Mac** (M1–M4)
- **macOS 13 Ventura** or newer
- **Xcode** (15 or newer) installed, opened once so it finishes setting up
- A webcam (the built-in FaceTime camera works)

## Build and run

Open **Terminal** and run:

```bash
# 1. Get the code (first time only)
git clone https://github.com/omkoth10-oss/face-controller.git
cd face-controller

# 2. Build and start the app
swift run
```

The first build takes a minute. After that, `swift run` rebuilds only what changed.

To get the latest version later:

```bash
cd face-controller
git pull
swift run
```

To stop the app: press **Cmd+Q** in its window, close the window, or press
**Ctrl+C** in Terminal. All three release any held keys first.

> If `swift run` complains about missing developer tools, run
> `xcode-select --install`, or `sudo xcode-select -s /Applications/Xcode.app`.

## Permissions (one-time setup)

The app needs two permissions. **Because you start it from Terminal, macOS gives
the permissions to Terminal**, not to "Face Controller". (If you use iTerm or the
VS Code terminal, give them to that app instead.)

1. **Camera**: the first time you run it, macOS asks *"Terminal would like to
   access the camera"*. Click **OK**.
   If you clicked Don't Allow: **System Settings → Privacy & Security → Camera →**
   turn on **Terminal**, then quit and re-run.
2. **Accessibility** (needed to press keys in other apps): macOS shows a dialog
   with an **Open System Settings** button. Go to **System Settings → Privacy &
   Security → Accessibility** and turn on **Terminal**. If Terminal isn't in the
   list, click **+** and add it from **Applications → Utilities → Terminal**.

The debug window shows a red box with these instructions (and a button that
opens the right settings page) whenever a permission is missing. If you've
turned a permission on and it still says missing, quit the app (and Terminal)
and run `swift run` again.

## How to use it

1. Run `swift run`. The debug window opens and says **"Look straight at the
   camera"**. Relax (mouth closed, eyebrows relaxed), look at the screen and hold
   still for 3 seconds. This records your *neutral* face; everything is measured
   relative to it.
2. Pick a **Mode** in the debug window (middle column).
3. Click into another app (TextEdit, Chrome, a game) and use your face.
4. **Recalibrate** any time: click the debug window and press **C** (or click
   **Recalibrate**). Do this whenever you change how you're sitting.

### Modes

| Mode | Head | Open mouth | Raise eyebrows |
|---|---|---|---|
| **Keys** | tilt up = hold **Space**, turn left = hold **A**, turn right = hold **D** | hold **left mouse button** | hold **E** |
| **Aim (mouse)** | moves the mouse pointer (like a joystick) | hold **left mouse button** | hold **E** |
| **Snake** | up / down / left / right = **one tap** of ↑ ↓ ← → | off | off |

- **Hold** gestures keep the key/button down for as long as you hold the gesture.
  A quick open-and-close of the mouth is a click; keeping it open is a held click
  (drag, hold to mine, etc.).
- **Aim mode:** the further you turn/tilt past a small deadzone, the faster the
  pointer moves; come back to neutral and it stops. Space/A/D are off in this
  mode because the head can't do both jobs at once yet (that's Phase 3). Use the
  **Sensitivity** slider to adjust speed.
- **Snake mode:** each head movement sends one arrow-key tap, then nothing else
  fires until your head is back in the center. That stops one movement from
  turning the snake several times.
- Switching mode releases everything first.

### Directions are from YOUR point of view

Turning your head to *your* left is "left", tilting *your* head up is "up",
whatever the camera does. The preview is mirrored like a selfie, and the app
corrects for camera mirroring automatically. The **Direction** pad (left column)
shows which way the app thinks you're moving; if a camera ever comes out
backwards, set `Directions.flipHorizontal` / `flipVertical` in `Config.swift`.

## Kill switch: ⌃⌥⌘K

**Control + Option + Command + K** turns control **ON/OFF** from any app, even a
full-screen game. Turning it off releases every held key and mouse button and
stops the pointer immediately. You hear a "tink" when it turns on and a "pop"
when it turns off.

## Safety: nothing is ever left stuck

Every held key and mouse button is released, and the pointer stops, when:

- control is turned off (kill switch or the button),
- your face isn't seen for more than **200 ms** (you look away, cover the camera,
  the camera freezes or is unplugged). The pointer stops at once, without waiting
  the 200 ms. If only the mouth/eyebrows can't be read for 200 ms, the mouse
  button and E are released,
- you switch mode or recalibrate,
- Accessibility permission is turned off while the app is running,
- the app quits (Cmd+Q, closing the window, Ctrl+C in Terminal, closing the
  Terminal window).

After any of these, gestures won't fire again until you've returned to neutral,
so you can't get a surprise key press. The only things that can't be caught are
a crash or `kill -9`; if a key ever seems stuck, tap that real key once (or click
the mouse).

## Tuning

Every threshold and timing is in one file:
**`Sources/FaceController/Support/Config.swift`**. Change a number, then stop the
app and `swift run` again.

**Gestures** (`Config.Gestures`). Each has `press`, `release` and `holdTime`:

| Gesture | press / release | holdTime | Unit |
|---|---|---|---|
| `tiltUp`, `tiltDown`, `turnLeft`, `turnRight` | 10 / 6 | 0.080 s | degrees from neutral |
| `mouthOpen` | 30 / 18 | 0.080 s | % of the distance between your eyes, above neutral |
| `eyebrowsRaise` | 8 / 5 | 0.080 s | % of the distance between your eyes, above neutral |

- `press`: go past this to press. Lower = easier to trigger, more false triggers.
- `release`: come back below this to release. Keep it a few units below `press`
  so it doesn't flicker.
- `holdTime`: how long you must stay past `press` before it fires. Lower =
  faster, more accidental presses. Releasing is always immediate.

**Which gesture does what** (`Config.Mapping`): the `keys`, `aim` and `snake`
lists. Change a key by changing its key code (e.g. `kVK_ANSI_E` → `kVK_ANSI_F`) and
its label.

**Other settings**

| Setting | Default | What it does |
|---|---|---|
| `Directions.flipHorizontal` / `flipVertical` | false | Flip left/right or up/down if the Direction pad is backwards for your camera. |
| `Aim.defaultSensitivity` | 1.0 | Starting value of the Sensitivity slider (0.25–3). |
| `Aim.horizontalDeadzone` / `verticalDeadzone` | 2.5° / 2.0° | No pointer movement this close to neutral (stops drift). |
| `Aim.horizontalFullSpeedAngle` / `verticalFullSpeedAngle` | 15° / 10° | Head angle where the pointer reaches full speed. |
| `Aim.maxSpeedX` / `maxSpeedY` | 1500 / 1000 | Full speed in screen points per second. |
| `Aim.curveExponent` | 1.8 | Response curve: 1 = straight line; higher = slower and more precise near the center. |
| `Aim.smoothingTime` | 0.05 s | Eases speed changes between camera frames. 0 = none. |
| `Snake.pressDegrees` | 10° | Head movement needed for one Snake turn. |
| `Snake.neutralDegrees` | 5° | How close to center your head must come back before the next turn. |
| `Snake.holdTime` | 0.050 s | Hold time for Snake turns (shorter than normal, for speed). |
| `Smoothing.minCutoff` | 2.5 | Jitter removal when still. Lower = smoother but laggier. |
| `Smoothing.beta` / `expressionBeta` | 0.1 / 0.03 | How quickly smoothing turns off when the head / face moves fast. |
| `Smoothing.enabled` | true | `false` uses raw values (fastest, most jittery). |
| `Tracking.expressionsEnabled` | true | `false` skips mouth/eyebrow tracking (saves a few ms per frame). |
| `Safety.faceLostTimeout` | 0.200 s | How long the face can be missing before everything is released. |
| `Calibration.duration` | 3 s | How long calibration records your neutral face. |
| `Camera.preferredFrameRate` | 60 | Frame rate requested. Built-in Mac cameras usually max out at 30. |
| `Safety.killSwitch...` | ⌃⌥⌘K | The kill-switch shortcut. |

**Tips**

- A gesture triggers when you don't want it to → raise its `press` (e.g. head
  12–14°, mouth 35–40%) or its `holdTime` (e.g. 0.12).
- Too hard to trigger or too slow → lower `press` or `holdTime` (e.g. 0.05).
- Flickers on and off → widen the gap between `press` and `release`.
- Talking clicks the mouse → raise `mouthOpen.press`.
- Numbers jump around even when you're still → lower `Smoothing.minCutoff`
  (e.g. 1.5).
- Aiming drifts when you're still → raise the aim deadzones. Too slow near the
  center → lower `curveExponent` (e.g. 1.3).

## What the debug window shows

- **Camera preview** (mirrored like a selfie), the camera mode in use, and whether
  the camera's frames are mirrored (corrected automatically).
- **Direction** pad: which way the app thinks *you* are moving your head.
- **Control** ON/OFF, the kill-switch hotkey, why input is blocked (if it is),
  and what's held right now.
- **Mode** picker: Keys / Aim (mouse) / Snake.
- **Calibration** status, your neutral face, and "jitter" (how much each value
  wobbled while you held still; small is good). Orange warnings mean a reading
  is noisy compared with its threshold.
- **Gestures** table: for every gesture, what it does in this mode, its live
  value, a bar with the press (red) and release (orange) lines, the thresholds,
  and its status (ready, hold %, **HELD** / **TAP**, back to neutral, off).
- **Head-to-mouse aiming**: Sensitivity slider, head offset and pointer speed.
- **Head and face**: pitch / yaw / roll (raw and vs. neutral), mouth and eyebrow
  values.
- **Speed**: camera FPS, dropped frames, Vision time (and the landmarks part),
  total processing per frame, camera delay, and **frame → key/click latency**
  (from the moment the camera captured the frame to the moment the event was sent).
- **Recent events**: calibrations, mode changes, safety releases, permission changes.

## How the code is organized

```
Sources/FaceController/
  App/          FaceControllerApp.swift (entry point), AppController.swift (wires everything)
  Camera/       CameraManager.swift: AVFoundation camera, 60 fps if possible, drops late frames
  Tracking/     HeadPoseTracker.swift (Vision → head angles + landmarks),
                ExpressionReader.swift (landmarks → mouth / eyebrows),
                PlayerDirections.swift (camera view → YOUR left/right/up/down),
                OneEuroFilter.swift (smoothing)
  Calibration/  Calibrator.swift: records your neutral face
  Gestures/     GestureCatalog.swift (gestures, modes, bindings),
                ThresholdGesture.swift (hysteresis + hold time → press / release)
  Aim/          AimController.swift: head → mouse speed (deadzone, curve, 120 Hz output)
  Input/        VirtualInput.swift: CGEvent keys, mouse button and movement; tracks what's held
  Engine/       ControlEngine.swift: the tight loop, camera → Vision → gestures → output
  Safety/       GlobalHotKey.swift (kill switch), ExitGuard.swift (release on quit), Permissions.swift
  UI/           DebugView.swift, GestureTable.swift, DirectionPad.swift, Components.swift, CameraPreview.swift
  Support/      Config.swift (ALL tunable numbers and key mappings), Timing.swift
```

## Notes

- Some games with anti-cheat (e.g. Valorant) may block simulated input. Casual
  and single-player games are the focus.
- Every push is compiled on a real Mac by GitHub Actions
  (`.github/workflows/build.yml`).
- Testing checklist: see [TESTING.md](TESTING.md).
