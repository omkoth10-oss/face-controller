# Face Controller

A free Mac app that turns your webcam into a game controller using head and face
gestures. It sends real keyboard input at the system level, so it works with
almost any game.

> **Status: Phase 1 prototype.** One gesture: **tilt your head UP to hold Space**.
> It also has a debug window that shows exactly what the tracker sees, how close
> you are to triggering, and how fast everything is.

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
   camera"**. Relax, look at the screen and hold still for 3 seconds. This records
   your *neutral* head position; everything is measured relative to it.
2. Click into another app (TextEdit, Chrome, a game).
3. **Tilt your head up** (chin up) past the red line on the bar → **Space is held**.
   Come back to neutral (below the orange line) → **Space is released**.
4. **Recalibrate** any time: click the debug window and press **C** (or click
   **Recalibrate**). Do this whenever you change how you're sitting.

## Kill switch: ⌃⌥⌘K

**Control + Option + Command + K** turns control **ON/OFF** from any app, even a
full-screen game. Turning it off releases every held key immediately. You hear a
"tink" when it turns on and a "pop" when it turns off.

## Safety: keys are never left stuck

Every held key is released when:

- control is turned off (kill switch or the button),
- your face isn't seen for more than **200 ms** (you look away, cover the camera,
  the camera freezes or is unplugged),
- Accessibility permission is turned off while the app is running,
- the app quits (Cmd+Q, closing the window, Ctrl+C in Terminal, closing the
  Terminal window).

After any of these, the gesture won't fire again until you've returned to
neutral, so you can't get a surprise key press. The only things that can't be
caught are a crash or `kill -9`; if Space ever seems stuck, tap the real Space
bar once.

## Tuning

Every threshold and timing is in one file:
**`Sources/FaceController/Support/Config.swift`**. Change a number, then stop the
app and `swift run` again.

| Setting | Default | What it does |
|---|---|---|
| `TiltUp.pressDegrees` | 10° | How far you tilt up to **press** Space. Lower = easier to trigger, more false triggers. |
| `TiltUp.releaseDegrees` | 6° | Come back below this to **release**. Keep it a few degrees below `pressDegrees` so the key doesn't flicker. |
| `TiltUp.holdTime` | 0.080 s | How long you must stay past the press line before Space is pressed. Lower = faster, more accidental presses. |
| `TiltUp.flipDirection` | false | Set to `true` if the **Tilt up** number goes *negative* when you tilt your head up. |
| `Smoothing.minCutoff` | 2.5 | Jitter removal when your head is still. Lower = smoother but laggier. |
| `Smoothing.beta` | 0.1 | How quickly smoothing turns off when you move fast. Higher = snappier. |
| `Smoothing.enabled` | true | `false` uses raw angles (fastest, most jittery). |
| `Safety.faceLostTimeout` | 0.200 s | How long the face can be missing before all keys are released. |
| `Calibration.duration` | 3 s | How long calibration records your neutral position. |
| `Camera.preferredFrameRate` | 60 | Frame rate requested. Built-in Mac cameras usually max out at 30. |
| `Safety.killSwitch...` | ⌃⌥⌘K | The kill-switch shortcut. |

**Tips**

- Space triggers when you don't want it to → raise `pressDegrees` (e.g. 12–14)
  or `holdTime` (e.g. 0.12).
- Too hard to trigger or too slow → lower `pressDegrees` (e.g. 7–8) or
  `holdTime` (e.g. 0.05).
- Space flickers on and off → widen the gap between `pressDegrees` and
  `releaseDegrees`.
- Numbers jump around even when you're still → lower `Smoothing.minCutoff`
  (e.g. 1.5).

## What the debug window shows

- **Camera preview** (mirrored, like a mirror) and the camera mode in use.
- **Control** ON/OFF, the kill-switch hotkey, and why keys are blocked (if they are).
- **Calibration** status and your neutral angles. "Jitter" is how much your head
  moved while calibrating (under ~2° is good).
- **Tilt up** in degrees, a bar with the press (red) and release (orange) lines,
  "% of the way to pressing", and whether **Space is held**.
- **Head**: pitch / yaw / roll, raw and relative to neutral.
- **Speed**: camera FPS, dropped frames, Vision time per frame, total processing
  time per frame, camera delay, and **frame → key event latency** (from the
  moment the camera captured the frame to the moment the key event was sent).
- **Recent events**: calibrations, key releases for safety reasons, permission changes.

## How the code is organized

```
Sources/FaceController/
  App/          FaceControllerApp.swift (entry point), AppController.swift (wires everything)
  Camera/       CameraManager.swift: AVFoundation camera, 60 fps if possible, drops late frames
  Tracking/     HeadPoseTracker.swift (Apple Vision → pitch/yaw/roll), OneEuroFilter.swift (smoothing)
  Calibration/  Calibrator.swift: records your neutral head position
  Gestures/     ThresholdGesture.swift: hysteresis + hold time → press / release
  Input/        KeyboardOutput.swift: CGEvent key presses, tracks held keys
  Engine/       ControlEngine.swift: the tight loop, camera → Vision → gesture → key
  Safety/       GlobalHotKey.swift (kill switch), ExitGuard.swift (release on quit), Permissions.swift
  UI/           DebugView.swift, CameraPreview.swift
  Support/      Config.swift (ALL tunable numbers), Timing.swift
```

## Notes

- Some games with anti-cheat (e.g. Valorant) may block simulated input. Casual
  and single-player games are the focus.
- Every push is compiled on a real Mac by GitHub Actions
  (`.github/workflows/build.yml`).
- Testing checklist: see [TESTING.md](TESTING.md).
