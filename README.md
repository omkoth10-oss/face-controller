# Face Controller

A free Mac app that turns your webcam into a game controller using head and face
gestures. It sends real keyboard input at the system level, so it works with
almost any game.

> **Status: Phase 3 prototype.** Head gestures (tilt up, turn left/right),
> facial expressions (open mouth, raise eyebrows), head-to-mouse aiming, a
> Snake mode for Google Snake, and a Minecraft preset with three switchable ways
> for the head to both walk and aim. A debug window shows exactly what the
> tracker sees, every gesture's live value, how close you are to triggering, and
> how fast everything is.

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
4. **Recenter** any time with **⌃⌥⌘R** (from any app), or **R** / the
   **Recenter now** button in the debug window: wherever your head is right now
   becomes neutral, instantly. **Recalibrate** (**C**) does the full 3-second
   calibration again, including your mouth and eyebrows.

### Modes

| Mode | Head | Open mouth | Raise eyebrows |
|---|---|---|---|
| **Keys** | tilt up = hold **Space**, turn left = hold **A**, turn right = hold **D** | hold **left mouse button** | hold **E** |
| **Aim (mouse)** | moves the mouse pointer (like a joystick) | hold **left mouse button** | hold **E** |
| **Snake** | up / down / left / right (or a quick flick) = **one tap** of ↑ ↓ ← → | off | off |
| **Minecraft** | walks and/or looks around, depending on the head option (below) | walk forward **W** (option 1) / break block = **left click** (2, 3) | jump = **Space** |

- **Hold** gestures keep the key/button down for as long as you hold the gesture.
  A quick open-and-close of the mouth is a click; keeping it open is a held click
  (drag, hold to mine, etc.).
- **Aim mode:** the further you turn/tilt past a small deadzone, the faster the
  pointer moves; come back to neutral and it stops. Space/A/D are off in this
  mode (the Minecraft preset is where the head does both). Use the
  **Sensitivity** slider to adjust speed.
- **Snake mode:** each head turn/tilt, or a quick **flick**, sends one arrow-key
  tap. After a turn, that direction's axis re-arms as soon as you come partway
  back (the other axis stays ready, so you can chain "left, then up"). Fast
  combos and diagonals send every turn: turns that come very close together are
  spaced a few ms apart, never dropped. The **extra-turn guard** (on by default)
  stops small side-effect flicks from turning the snake: while your head swings
  back past the center after a turn, or while the other direction is moving
  faster, a flick must reach the full press threshold instead of 30% of it.
  Optional bounce-back and double-turn blocks can be switched on in the Snake
  panel (off by default; Google Snake ignores reversals and repeats itself). The
  **Turn log** lists every turn and how far your head went for it, shows in red
  any turn that didn't go through (with the reason), and in orange any flick the
  extra-turn guard ignored. All of it is tunable live with sliders in
  the **Snake tuning** panel; your values are saved between launches. See
  TESTING.md for a tuning guide.
- Switching mode releases everything first.

### Minecraft preset (Phase 3: the head walks AND aims)

Made for **Minecraft Classic** in the browser (**classic.minecraft.net**: W A S D
walk, Space jumps, the mouse looks around, left click breaks a block). Walking
and looking around both want the head, so there are three options to try. Pick
one in the **Minecraft** panel (right column); it's saved.

1. **Face moves, head aims.** The head only looks around (like the mouse). Open
   your mouth to walk forward (W), raise your eyebrows to jump (Space). Simple,
   but nothing is left for clicking.
2. **Mode switch.** Tilt your head toward either shoulder (like a curious dog,
   about 15°) and back: the head switches between **MOVE** (tilt up = W, down = S,
   left = A, right = D) and **AIM** (look around). Each job has its own sound.
   While your head is tilted, walking and aiming pause, so the switch itself
   never walks or turns the view, and every switch lets go of everything. Mouth =
   break block (left click), eyebrows = jump. Tilting toward a shoulder was picked
   because walking and aiming never use it, Vision measures it reliably, and
   people rarely do it by accident while playing.
3. **Split zones.** Small head moves look around. Go further than the **walk
   zone** (default 11°) and you also walk that way (up = W, down = S, left = A,
   right = D) while still turning. Mouth = break block, eyebrows = jump.

A small label floats at the top of the screen over the game (**AIM** / **MOVE** /
**OFF**, plus what's held). It never takes the keyboard or mouse from the game,
and can be switched off in the panel. Play the game in full-screen Chrome so the
pointer stays inside it. The floating center, kill switch and every safety rule
work the same in all three options. TESTING.md section 8 has a test for each.

### Floating center (on in every mode)

The center follows your head: when your head **rests still near the center**,
the center slowly slides to where your head is, so leaning, slouching or moving
your chair doesn't add up to accidental presses. Moves are measured from where
you are now. It **never** moves while something is happening: a key held (A, D,
Space), a turn about to fire or re-arming, or the pointer moving. "Near the
center" means: Keys mode, within half the press threshold (5°); Aim mode, inside
the deadzone (so the pointer can't move); Snake, inside the re-arm zone.

The **Floating center** box (middle column) has an on/off switch for the current
mode (each mode remembers its own) and a **Follow time** slider (how quickly the
center catches up; default about 1.5 s). Both are saved. On the Direction pad the
**purple ring** is the floating center; the grey cross is where you calibrated.
**Recenter** (⌃⌥⌘R) snaps the center to your head instantly.

### Directions are from YOUR point of view

Turning your head to *your* left is "left", tilting *your* head up is "up",
whatever the camera does. The preview is mirrored like a selfie, and the app
corrects for camera mirroring automatically. The **Direction** pad (left column)
shows which way the app thinks you're moving; if a camera ever comes out
backwards, set `Directions.flipHorizontal` / `flipVertical` in `Config.swift`.

## Hotkeys (work from any app)

- **⌃⌥⌘K** (Control + Option + Command + K): kill switch, see below.
- **⌃⌥⌘R** (Control + Option + Command + R): recenter (your head's current
  position becomes neutral). Short sound when it happens.

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
| `Snake.default...` | 8.5°, 45%, 40 ms, 25%, 80°/s | Starting values of the Snake sliders (press, re-arm, hold, smoothing, flick speed): the owner's tuned values. Normally just use the sliders. |
| `Snake.defaultMinTurnInterval` | 45 ms | Starting value of the "Min time between turns" slider. Turns closer than this are sent a little later, never dropped. |
| `Snake.defaultExtraTurnGuardEnabled` | on | Starting state of the Extra-turn guard switch in the Snake panel. |
| `Snake.extraTurnGuardFraction` | 1.0 | When the guard is suspicious of a flick (swing-back or leak), it must reach this fraction of the press threshold to fire. |
| `Snake.swingBackWindow` / `swingBackEndFraction` | 0.5 s / 0.25 | The swing-back check lasts at most this long after re-arming, or until the head slows below this fraction of the flick speed. |
| `Snake.reattemptDipFraction` | 0.5 | "Not re-armed yet" is only logged after the head came back this fraction of the press threshold from its furthest point. |
| `Snake.defaultBounceBlockEnabled` / `defaultSameDirectionBlockEnabled` | off / off | Starting state of the two optional block switches in the Snake panel. |
| `Snake.bounceBlock` | 0.35 s | When the bounce-back block is ON: after re-arming, ignore turns the opposite way on that axis for this long. |
| `Snake.sameDirectionCooldown` | 0.25 s | When the double-turn block is ON: the same direction can't fire twice within this time. |
| `FloatingCenter.snakeZoneFraction` / `snakePauseAfterTurn` | 0.5 / 0.8 s | Snake: the center only follows within half the re-arm zone, and waits this long after each turn. |
| `Minecraft.defaultOption` | option 1 | Head option picked on first launch (then the panel's choice is saved). |
| `Minecraft.faceMovesBindings` / `actionBindings` / `headWalkBindings` | see Minecraft preset | What each gesture does in the options (keys W A S D, Space, left click). |
| `Minecraft.defaultSwitchTiltDegrees` / `switchHoldTime` | 15° / 0.15 s | Option 2: tilt toward a shoulder this far, this long, to switch MOVE ↔ AIM (slider). |
| `Minecraft.switchReleaseFraction` / `switchPauseFraction` | 0.5 / 0.5 | Option 2: come back below half the tilt before the next switch; walking/aiming pause while tilted past half. |
| `Minecraft.moveSound` / `aimSound` | Submarine / Glass | Option 2: sound for switching to MOVE / to AIM. |
| `Minecraft.defaultMoveDegrees` / `moveHoldTime` | 8° / 60 ms | Option 2 in MOVE: turn/tilt this far to walk (slider); releases at 60% of it. |
| `Minecraft.defaultWalkZoneDegrees` / `walkHoldTime` | 11° / 80 ms | Option 3: past this the head also walks (slider); stops below 75% of it. |
| `Snake.flickMinFraction` / `flickOnsetFraction` | 0.3 / 0.5 | How far out a flick must be (fraction of press), and how "early" a flick may fire. |
| `FloatingCenter.defaultEnabled` / `defaultFollowTime` | on / 2 s | Starting values of the Floating center switch and slider (your values are saved). |
| `FloatingCenter.stillSpeed` / `restDwell` | 15°/s / 0.25 s | How still, and for how long, your head must rest before the center follows. |
| `FloatingCenter.pauseAfterOutput` | 0.3 s | After a key/turn fires, the center waits this long. |
| `Recenter.keyCode` / `modifiers` | ⌃⌥⌘R | The recenter hotkey. |
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
- **Mode** picker: Keys / Aim (mouse) / Snake / Minecraft.
- **Minecraft** panel (Minecraft mode only): head option picker, what every
  gesture does in that option, option 2's big MOVE / AIM indicator with the
  shoulder-tilt bar and a **Switch now** button, the option's sliders (switch
  tilt, walk threshold, walk zone), and the overlay switch.
- **Snake tuning** (Snake mode only): Recenter button; "Right now" lines that
  say exactly why a turn isn't firing; last turn and its frame → key latency;
  live sliders; your values with a Copy button.
- **Floating center**: on/off for the current mode, Follow time slider, what the
  center is doing right now ("following", "paused: A held", ...), and how far it
  has moved.
- **Turn log** (Snake mode only): each turn (✓, with time, latency and how far
  your head went), each blocked turn (red ✗, with the reason) and each flick the
  extra-turn guard ignored (orange ✗).
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
                FloatingCenter.swift (the center that follows your resting head),
                OneEuroFilter.swift (smoothing)
  Calibration/  Calibrator.swift: records your neutral face
  Gestures/     GestureCatalog.swift (gestures, modes, bindings),
                ThresholdGesture.swift (hysteresis + hold time → press / release),
                SnakeController.swift (Snake rules + saved slider settings),
                HeadOptions.swift (Minecraft's three head options, saved settings,
                option 2's tilt-to-switch gesture)
  Aim/          AimController.swift: head → mouse speed (deadzone, curve, 120 Hz output)
  Input/        VirtualInput.swift: CGEvent keys, mouse button and movement; tracks what's held
  Engine/       ControlEngine.swift: the tight loop, camera → Vision → gestures → output
  Safety/       GlobalHotKey.swift (kill switch), ExitGuard.swift (release on quit), Permissions.swift
  UI/           DebugView.swift, SnakePanel.swift, MinecraftPanel.swift,
                GameOverlay.swift (label over the game), FloatingCenterBox.swift (+ Turn log),
                GestureTable.swift, DirectionPad.swift, Components.swift, CameraPreview.swift
  Support/      Config.swift (ALL tunable numbers and key mappings), Timing.swift
```

## Notes

- Some games with anti-cheat (e.g. Valorant) may block simulated input. Casual
  and single-player games are the focus.
- Every push is compiled on a real Mac by GitHub Actions
  (`.github/workflows/build.yml`).
- Testing checklist: see [TESTING.md](TESTING.md).
