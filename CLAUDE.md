# Face Controller — Project Brief

> Claude: read this at the start of every session. After every change, update this file (including **Progress Log** and **Next Steps**), then commit and push.

## The idea
A free Mac app that turns your webcam into a full game controller. Head movements and facial expressions (tilt head, turn head, raise eyebrows, open mouth, smile) press keys and move the mouse. It sends real-looking keyboard/mouse input at the OS level, so it works with almost any game without the game needing to support it.

**The whole game must be playable with only your face: movement, actions, AND aiming. No hands needed.**

Working name: TBD (placeholder "Face Controller").

## Who it's for
1. **Main audience: disabled gamers** with limited hand/arm use but good head/face control. Current options (adaptive controllers, QuadStick, eye trackers) cost $90–$500+. This needs only a webcam and is free.
2. **Also: regular gamers** who think it's fun. Same app, no separate hybrid mode.

## Core decisions (from owner, 2026-10-18)
- **Fully face-controlled.** Not hybrid with mouse/keyboard.
- **Both head movements and facial expressions** are inputs.
- **Head-controlled mouse aiming is important** and part of v1.
- **Must work great in all games, including fast-reflex games** (shooters, platformers). Speed and low latency are top priorities.
- **No voice commands.** Face only.
- **Native Swift app** from the start (no Python prototype).
- **Dev machine:** Apple Silicon Mac (M1–M4).
- **Directions are always from the player's point of view** (decided 2026-10-18): turning your head to YOUR left = left in the game, tilting YOUR head up = up, no matter whether the camera image is mirrored or not. The camera preview should be mirrored like a selfie so it feels natural, and the code must correct for any mirroring so controls never feel backwards.

- **Floating center (owner request, 2026-10-18):** the center should follow the player's head: wherever the head comes to rest becomes the new center, so moves are measured from where you are now, not from a fixed calibrated spot. **ON by default in ALL modes and all games** (owner, 2026-10-18), not just Snake. Must not break held keys or aiming: the center only moves while the head is resting near center, never while a direction is firing/held or the pointer is moving. Speed setting + per-mode off switch stay available.

### Open design problem: head does two jobs
Head movement is wanted for both movement keys and mouse aiming. These conflict. Options to explore and test:
- Head = aim, facial expressions = movement/actions.
- Mode switch gesture (e.g., hold a gesture to swap head between "move" and "aim").
- Per-game presets choose which mapping fits.
Decide by prototyping and testing, not guessing. **Being tested (2026-10-19):** three switchable options in a Minecraft preset (classic.minecraft.net): 1 "Face moves, head aims", 2 "Mode switch" (tilt to a shoulder), 3 "Split zones". Owner picks one after TESTING.md section 8.

## Why it's worth building (the gap)
- Google Project Gameface: Windows only, clunky setup, accessibility tool rather than gaming product.
- SensePilot: PC, not Mac.
- macOS built-in Head Pointer: cursor/click only, not built for game keybinds.
- Hawkeye Access: needs an iPhone TrueDepth camera.
- GitHub hobby projects: code demos, not installable apps.
- **PlayAbility** (strongest competitor): Windows only, webcam facial gestures (~50 expressions + custom), maps to keyboard/mouse/controller/Xbox Adaptive Controller. Paid subscription with a limited free tier (limits have changed over time). No Mac version.
- **Google Project GameFace's repo was archived (read-only) on Sep 5, 2025.** There's room for an actively maintained open-source successor.
- **No polished, gaming-first, Mac-friendly, fully face-controlled app exists.**
- **How we win:** not more buttons than PlayAbility, but easier, more precise, more personalized, private (100% offline), open source, Mac-first, and completely free with nothing locked.

## Long-term vision (from owner, 2026-10-18)
"One system that turns whatever movements a person CAN make into whatever inputs a game NEEDS." An adaptive-input platform, not just a webcam controller. Build the core extremely well first; the backlog below grows it over time.

## Goals
- Fun learning project + college application project.
- Free and open source (GitHub), optional donation link. Impact over money.
- Real users matter more than features. Target: ~1,000 downloads year one, 50+ real active users, 1+ strong user story.
- No disabled testers yet: reach out to AbleGamers (Player Panels), Reddit communities, and local groups once there's a demo.

## Product format (decided 2026-10-18)
- **Downloadable app** does the real work. A website alone can't: browsers block sites from pressing keys in other apps/games.
- **Website** (built around launch): landing page, demo video, Download button.
- **Browser demo** on the website: a simple face-controlled jump game so people can try it before downloading.
- Order: app first, website + browser demo at launch.

## Tech plan
- **Language/UI:** Swift + SwiftUI, native macOS app (menu bar app + settings window). Target Apple Silicon.
- **Camera:** AVFoundation, request 60 fps when available, low resolution for speed.
- **Face tracking:** Apple Vision face landmarks first (fast, built-in, on-device). If expression detection (eyebrows, mouth, smile) isn't reliable enough, evaluate MediaPipe Face Landmarker blendshapes.
- **Input:** CGEvent for key presses and mouse movement.
- **Permissions:** Camera, Accessibility, Input Monitoring. Onboarding must guide users clearly.
- **Distribution:** GitHub release first; later signing/notarization ($99/yr Apple Developer) to avoid "unidentified developer" warnings.
- **Build:** Swift Package Manager executable (`Package.swift`, swift-tools 5.9, macOS 13+), run with `swift run`. No third-party dependencies.
- **CI:** GitHub Actions (`.github/workflows/build.yml`) runs `swift build` (debug + release) on a macOS runner on every push to `main` and `claude/**` branches, PRs to `main`, and by hand. Cloud sessions can't compile macOS code, so this is the compile check: don't call work done until it's green.

## Code map (Phase 2)
All code is in `Sources/FaceController/`:
- `Support/Config.swift`: **every tunable number and the key mappings** (camera, smoothing, directions flips, gesture thresholds, per-mode bindings, aim, Snake, safety, kill-switch key).
- `Camera/CameraManager.swift`: AVFoundation capture, picks fastest fps (≤60) then size closest to 640x480, drops late frames, asks for unmirrored frames and reports whether they're mirrored.
- `Tracking/HeadPoseTracker.swift`: Vision face rectangles (rev 3) → pitch/yaw/roll, then face landmarks (76 points) on that face. `Tracking/ExpressionReader.swift`: landmarks → mouth open / eyebrow height in % of eye distance. `Tracking/PlayerDirections.swift`: the ONE place camera angles become the player's left/right/up/down (mirror-corrected). `Tracking/FloatingCenter.swift`: the floating center (rest detection, busy rules applied by the engine, saved per-mode settings). `Tracking/OneEuroFilter.swift`: smoothing.
- `Calibration/Calibrator.swift`: neutral face (head angles + mouth + eyebrows) = median of 3 s of face-visible samples, plus jitter per value.
- `Gestures/GestureCatalog.swift`: gesture IDs, modes (Keys / Aim / Snake / Minecraft), bindings (hold/tap). `Gestures/HeadOptions.swift`: Phase 3's three head options for the Minecraft preset (`HeadOption`, `HeadJob` MOVE/AIM, `MinecraftSettings` saved in UserDefaults with tolerant decoding, per-option bindings and walk thresholds) and option 2's `HeadJobSwitch` (tilt-to-a-shoulder gesture). `Gestures/ThresholdGesture.swift`: hysteresis + hold time → press/release (Keys/Aim). `Gestures/SnakeController.swift`: Snake rules (two independent axes, per-axis re-arm, flick + early-onset flick detection, extra-turn guard (swing-back + leak), optional bounce-back / double-turn blocks, blocked/ignored-turn reasons, how far each turn went) + `SnakeSettings` (live slider values, saved in UserDefaults, tolerant decoding).
- `Aim/AimController.swift`: head offset → pointer speed (deadzone, power curve, sensitivity), eased, sent by its own 120 Hz timer; stops when data goes stale.
- `Scroll/ScrollController.swift`: Scroll mode: `ScrollOption` (smooth / shorts), `ScrollSettings` (saved, tolerant decoding, per-option bindings), `ScrollMotion` (pure: tilt → target speed with deadzone + curve, eased speed → whole points; unit tested), `ScrollController` (120 Hz timer posting scroll-wheel events, instant stop on safety, stale-data stop).
- `Input/VirtualInput.swift`: CGEvent keys, left mouse button, mouse movement (with deltas, for pointer-locked games) and scroll-wheel events (pixel units, flags cleared); tracks what's held; "block reasons" (control off, calibrating, no permission, quitting) release everything and refuse input.
- `Engine/ControlEngine.swift`: the tight loop on one serial queue (camera → Vision → gestures/aim/Snake/Minecraft/Scroll → output), live `bindings` + `thresholds(for:)` (per mode, and in Minecraft per option and MOVE/AIM job), one `taps` SnakeController shared by Snake and Scroll's Shorts (each with its own saved settings), mode switching, adjustable neutral (recenter + floating center in all modes, with per-mode zone and "busy" rules), Snake Turn log, face-lost and expression-lost rules, 50 ms watchdog, snapshots for the UI.
- `Safety/`: `GlobalHotKey.swift` (Carbon kill switch), `ExitGuard.swift` (atexit + SIGINT/SIGTERM/SIGHUP/SIGQUIT release everything), `Permissions.swift`.
- `App/`: `FaceControllerApp.swift` (@main, activation policy, window size; closing the debug window quits even with the overlay showing), `AppController.swift` (wiring, permissions, kill switch + recenter hotkeys, mode/sensitivity/Snake/Minecraft settings, overlay, MOVE/AIM sounds).
- `UI/`: `DebugView.swift` (3-column layout), `SnakePanel.swift` (Snake live tuning), `MinecraftPanel.swift` (head option picker, cheat sheet, MOVE/AIM indicator, sliders), `ScrollPanel.swift` (Scroll option picker, live speed, sliders, switches; Shorts reuses `SnakePanel(forShorts: true)`), `GameOverlay.swift` (non-activating, click-through always-on-top label over the game), `FloatingCenterBox.swift` (floating center controls + Snake `TurnLogView`), `GestureTable.swift`, `DirectionPad.swift` (head dot + floating-center ring), `Components.swift`, `CameraPreview.swift`.

## Features (priority order)
**Must-haves**
1. No false triggers: hold time before firing, dead zones for small movements.
2. One-click calibration ("look straight for 3 seconds"), recalibrate anytime.
3. Pause gesture (e.g., eyes closed 2 sec) so talking or laughing doesn't trigger actions.
4. Live feedback overlay: active keys + how close each gesture is to triggering.
5. Simple mapping screen: pick gesture, press key, done.
6. Head-to-mouse aiming with adjustable sensitivity and smoothing.

**Make people want it**
7. Ready-made game presets: Minecraft, Roblox, Geometry Dash, browser games, a shooter preset.
8. Hold / tap / toggle modes per gesture (toggle reduces neck strain).
9. Sensitivity slider per gesture.
10. Speed mode for fast games (see below).

**Extras**
11. Small-gesture mode for limited movement.
12. Practice mini-game to learn gestures (great for demo video).
13. Export/import profiles, community sharing.
14. Fatigue/break reminders.
15. Works in low light and with glasses.

## Speed mode (fast games / shooters)
- 60 fps camera, low-resolution tracking.
- Short hold time (~50 ms) vs ~200 ms default.
- Tiny fast gestures (eyebrow raise, mouth open) for jump/shoot.
- Detect motion onset (quick flicks), not just final position.
- Single tight loop: camera → tracking → input, no extra waits. Measure end-to-end latency.
- Honest limit: face aiming won't match a mouse in competitive shooters; aim for "fun and playable."
- Anti-cheat games (e.g., Valorant) may block simulated input. Focus on casual and single-player games.

## Roadmap
1. **Swift prototype** (2–3 sessions): camera + Vision tracking, head tilt up = hold Space, calibration, debug window. Test in TextEdit → Chrome dino game → Minecraft. *(Built 2026-10-18, awaiting owner testing.)*
2. **Core gestures + aiming** (4–6 sessions): turn left/right, mouth open, eyebrow raise, head-to-mouse aim, false-trigger fixes, latency measurement. *(First version built 2026-10-19 with a Snake mode for Google Snake; awaiting owner testing.)*
3. **Solve head move-vs-aim** (2–3 sessions): prototype options, test, pick one. *(Three options built 2026-10-19 as a Minecraft preset; awaiting owner testing.)*
4. **Settings UI + mapping + onboarding** (3–5 sessions).
5. **Presets, speed mode, testing across games, bug fixes** (3–6 sessions).
6. **Release** (1–3 sessions): GitHub release, README, demo video, website + browser demo, Reddit (r/macgaming, r/disabledgamers, r/accessibility), Product Hunt.
7. **Outreach:** send demo video to AbleGamers, ask what's missing and for testers.

Key question for every tester: **"What made you stop using it?"**

## Ideas backlog (from owner, 2026-10-18)
Ideas the owner wants to *maybe* build. Not committed: ask before building anything here that isn't already in the roadmap. Grouped by when they fit.

**Fold into existing phases (high value, fits the plan)**
- **Precision engine** (Phase 2–5): per-axis sensitivity, deadzone, anti-deadzone, acceleration/deceleration, customizable response curve (e.g. 0.5°→2%, 2°→10%, 5°→30%, 10°→70%, 15°→100%), smoothing, max speed, min movement threshold, axis inversion, recenter + recenter hotkey, temporary sensitivity modifier. Top technical priority for aiming.
- **"What can you control?" calibration/onboarding** (Phase 4): guided steps (head left/right/up/down as far as comfortable, open mouth, blink each eye, eyebrows, smile) that learn comfortable range, max range, neutral, gesture reliability, and noise/tremor, then auto-build a profile. Possible killer feature.
- **Tap / Hold / Toggle / Repeat** per gesture (Phase 4–5; extends feature 8).
- **Control Tester** (Phase 4): live view of exactly which keys, mouse movement, and stick values the user's movements produce.
- **Step-by-step troubleshooting** (Phase 4): Camera ✓ → Face tracking ✓ → Gesture ✓ → Output ✓ → Game ✕, in plain language.
- **Latency breakdown visible in settings** (tracking / processing / output / total). Phase 1 already shows most of this.
- **Advanced Mode** (Phase 4–5): raw landmarks, head pose, expression values, thresholds, curves, filters.
- **Unlimited profiles + import/export** (Phase 5).
- **100% offline, no account, no footage leaves the Mac**: a core promise (already true by design). Say it on the website.

**Version 2 (after first release)**
- Tremor filtering (Low/Medium/High/Custom, maybe adaptive to the user's baseline movement).
- Gesture combos/chords (e.g. smile + head left = Q).
- Auto-switch profiles when a game launches.
- Community profile library on the website, tagged by ability ("head-only", "one-eye", "limited neck movement"), ideally made by people with those same limitations.
- Website "Find your setup" questionnaire (what can you move? → recommended setup).
- Game compatibility database built from real user test reports (never claim untested games).
- Accessibility knowledge base ("limited neck movement → recommended inputs").
- Real disabled gamers demonstrating their setups on the website.

**Later / experimental (hard on Mac or with a webcam)**
- Eye + head hybrid aiming (head = big moves, eyes = fine aim). Webcam eye tracking is imprecise; prototype and test before promising.
- Virtual game controller (analog stick) output. macOS has no easy virtual-gamepad driver like Windows does; likely needs a DriverKit virtual HID device. Keyboard + mouse first.
- Voice as an extra layer. Conflicts with the current "no voice" decision; owner to revisit later.
- Adaptive hardware (switches, foot pedals, sip-and-puff, Tobii, Xbox Adaptive Controller).
- Windows and Linux versions. The ideas doc suggested Windows first; current decision stays **Mac first** (it's the gap: PlayAbility and GameFace are Windows). Revisit after the Mac version works.
- Therapist/professional tools, advanced ML personalization.

**Big risks to keep in mind:** competing with PlayAbility, computer-vision robustness (lighting, glasses, faces, cameras), neck fatigue, tremors, latency, anti-cheat (never promise "every game"), and building without disabled users. Recruit 5–20 disabled testers early.

## Rules for Claude
- Use whatever level of complexity the project actually needs, but keep it well-organized and commented, and briefly explain new or tricky parts in plain language so I understand how it works.
- Reliability and speed over new features.
- Don't add features outside this brief without asking.
- **After every change** (code, decision, or plan update): update this file to match, then commit and push to GitHub so cloud and local sessions always stay in sync.
- Note: cloud sessions can't use the webcam. Write code in the cloud; the owner tests on his Mac.
- **Player-perspective directions:** every direction (gestures, aiming, labels, docs) is from the player's point of view: their left is left, their up is up, regardless of camera mirroring. Convert camera angles to player directions only in `Tracking/PlayerDirections.swift`, keep the on-screen Direction pad accurate, and keep the `Config.Directions` flip settings working.

## Decisions and starting settings (Phases 1–2; Phase 2 untested on hardware)
- **Head angles:** `VNDetectFaceRectanglesRequest` revision 3 (fastest Vision face request; continuous pitch/yaw/roll).
- **Player directions:** tilt UP = Vision pitch NEGATIVE (worked in Phase 1 on the owner's Mac). Turn to the player's LEFT = Vision yaw POSITIVE in unmirrored frames (assumed from Vision's rotation convention: roll is documented counterclockwise-positive, pitch matched; yaw not yet confirmed on hardware). Frames are requested unmirrored; if a camera delivers mirrored frames the code flips yaw automatically. `Config.Directions.flipHorizontal` / `flipVertical` are manual overrides. Preview is mirrored like a selfie.
- **Expressions:** Vision face landmarks (revision 3, 76 points) run on the face already found. Mouth open = inner-lip height; eyebrows = brow centers above the eye-CORNER midpoints (corners don't move when blinking), both measured along the face's own up axis (roll-proof), in % of eye distance (distance-proof), relative to the calibrated neutral. If Vision isn't reliable enough, the fallback to evaluate is MediaPipe Face Landmarker blendshapes (explain and ask before switching).
- **Keys mode:** tilt up = hold Space, turn left = hold A, turn right = hold D, mouth open = hold left mouse button, eyebrows raised = hold **E** (picked: common "use/interact" key, opens Minecraft inventory; easy to see in testing).
- **Thresholds:** head 10° press / 6° release / 80 ms hold (all four directions). Mouth 30% / 18% / 80 ms. Eyebrows 8% / 5% / 80 ms. Release is immediate.
- **Aim mode:** head = joystick-style pointer speed. Deadzone 2.5° horizontal / 2.0° vertical; full speed at 15° / 10°; max 1500 / 1000 pt/s; power curve exponent 1.8; sensitivity slider 0.25–3×; 50 ms speed easing; 120 Hz output timer; events carry deltas so pointer-locked games work; left-button-held movement is sent as drag. Head keys (Space/A/D) are off in Aim mode; mouth/eyebrows still work. Toggling happens in the debug window's Mode picker (Phase 3 solves head doing both jobs).
- **Snake mode (owner request, 2026-10-19; reworked the same day after the first test):** head up/down/left/right = one TAP of ↑ ↓ ← → (30 ms key press). Two independent axes: an axis fires by POSITION (past the press threshold for the hold time) or by FLICK (head speed ≥ flick speed while ≥ 40% of the press threshold out; no hold time). After firing, only THAT axis waits; it re-arms once the head is back below re-arm fraction × press threshold on that axis (the other axis stays ready, so turns chain). After re-arming, flicks in the opposite direction are ignored for 0.25 s (the swing back). At most one turn per 100 ms. Snake uses raw head angles with its own lighter One Euro smoothing (slider) and skips the landmarks step. Live sliders (saved in UserDefaults, key `snakeSettings.v1`, decoded tolerantly so old/missing keys never wipe saved values), defaults (= the owner's tuned values since 2026-10-19; first defaults were press 5°, hold 30 ms, smoothing 30%, flick 60°/s): press 8.5°, re-arm 45%, hold 40 ms, smoothing 25% (~17 ms lag), flick 80°/s, min gap 45 ms, extra-turn guard on, blocks off. Expressions off. (2026-10-19, round 3:) flicks need ≥ 30% of the press threshold and fire on the two-frame average speed OR one frame earlier on motion onset (latest frame ≥ flick speed and the frame before ≥ 50% of it, same direction); every blocked attempt is reported once with its reason in the Turn log (time with ms, ✓ fired + latency / ✗ blocked + reason, last 14). (Round 4, after the owner's test showed fast back-to-back turns being eaten:) the bounce-back block (opposite direction within 0.35 s of re-arming) and the double-turn block (same direction within 0.25 s) are OFF by default, switchable in the Snake panel (saved: `bounceBlockEnabled`, `sameDirectionBlockEnabled`), because Google Snake ignores 180° reversals and repeated directions itself. Both axes may fire in the same frame. "Min time between turns" is a slider (0–150 ms, default 45 ms, saved as `minTurnInterval`) and only SPACES taps: a too-soon turn is sent later on the tracking queue (`asyncAfter`), never dropped. Turn log shows not-sent/blocked rows in red with the exact reason. (Round 5, after the owner reported occasional unwanted extra turns:) **extra-turn guard**, ON by default (switch in the Snake panel, saved as `extraTurnGuardEnabled`): a flick below the full press threshold is held back if it looks like a side effect of another movement: (a) SWING-BACK: the axis just re-armed after a fast return (≥ 25% of flick speed toward center) and the flick goes the opposite way of its last turn, for up to 0.5 s or until the head slows below 25% of flick speed; (b) LEAK: the other axis is moving faster this frame (both axes take in the frame before either decides). A held-back flick fires once it reaches the full press threshold (log note "after the extra-turn check"); if it comes back first it's logged as an ORANGE "IGNORED as an extra turn" line with how far it got. Each fired turn's log line gets "head went to N°" when its axis re-arms. "Not re-armed yet" is only reported after the head came back ≥ 50% of the press threshold from its furthest point (no more false alarms while the head is still moving out). Arrow key events carry the fn + numeric-pad flags like real arrow keys.
- **Minecraft preset (Phase 3, owner request 2026-10-19):** fourth mode "Minecraft" for Minecraft Classic in Chrome (classic.minecraft.net: W A S D, Space, mouse look, left click breaks). Head option picker (saved in UserDefaults `minecraftSettings.v1`, default option 1): **1 Face moves, head aims**: head = aim (same aim controller/deadzone/curve/sensitivity as Aim mode), mouth open = hold W, eyebrows = hold Space (no gesture left for clicking: ask the owner before adding one, e.g. smile). **2 Mode switch**: switch gesture = tilt toward EITHER shoulder (|roll| from neutral, `PlayerDirections.shoulderTilt`) ≥ 15° (slider 8–30°) held 0.15 s; re-arms below 50%; while |roll| ≥ 50% of it the head's walking/aiming pauses (keys released, pointer stopped) so the gesture can't walk or aim; each switch releases everything, plays Submarine (→ MOVE) / Glass (→ AIM), logs an event; starts in AIM; "Switch now" button. MOVE: head up/down/left/right = hold W/S/A/D at 8° (slider 4–15°), release 60%, hold 60 ms. AIM: head = aim. Mouth = hold left click, eyebrows = hold Space. **3 Split zones**: head always aims; past the walk zone (11°, slider 5–20°, release 75%, hold 80 ms) the head ALSO holds W/S/A/D that way; mouth = left click, eyebrows = Space. Floating center in Minecraft (own on/off, `minecraftEnabled`): zone = aim deadzone while the head aims, half the walk threshold in option 2 MOVE; busy while a head key is held/holding, the pointer moves, or the head is tilted to switch. An always-on-top overlay (non-activating NSPanel, click-through, all Spaces + full screen) shows AIM / MOVE / AIM + WALK / OFF and what's held; switch in the panel. Changing the option or a walk slider releases everything.
- **Scroll mode (owner request 2026-10-21, decisions made by Claude while the owner slept):** fifth mode "Scroll". Option picker saved in UserDefaults `scrollSettings.v1` (default Smooth). **Smooth scroll**: head up offset → `ScrollMotion.targetSpeed`: deadzone 4° (slider 2–10°), then maxSpeed 1500 points/s × t^2.0 × Speed (slider 0.25–3×, default 1×), full speed at 15°; tilt DOWN = scroll DOWN; the eased speed glides up with a 0.25 s time constant and down with 0.10 s, stops below 5 points/s; a 120 Hz timer posts `CGEvent` scroll-wheel events in PIXEL units (wheel1 negative = down, flags cleared), stops instantly on stopMoving() and after 0.12 s without fresh head data. "Reverse direction" switch (saved) in case a Mac scrolls backwards. Horizontal head movement does nothing. **Shorts**: ↓ = next, ↑ = previous (taps), driven by the same SnakeController as Snake mode with its own saved settings (`shortsSettings.v1`), defaults = Snake defaults except hold 120 ms (so looking down at the desk is less likely to skip) and the bounce-back + double-turn blocks ON (an extra flick = wrong video, unlike Snake); left/right is tracked (for the extra-turn guard's leak check) but never sent or logged; the Turn log shows "NEXT ↓" / "PREVIOUS ↑". **Mouth = tap Space (play/pause)**, ON by default (owner asked for it as a toggleable option), switch saved; needs the mouth open 0.30 s (talking/quick laughs don't pause). Expressions are skipped when the switch is off. Floating center has its own Scroll on/off (`scrollEnabled`): zone = scroll deadzone and busy while the scroll speed ≠ 0 (smooth); Snake's rules in Shorts.
- **Floating center (all modes, owner decision 2026-10-18):** replaces the Snake-only drift correction. Each frame, after gestures/aim/Snake run, the center (neutral head angles) eases toward the current smoothed head pose ONLY if: the head is within the mode's rest zone (Keys: 50% of the smallest bound head press threshold = 5°; Aim: inside the aim deadzone = 2°; Snake: 50% of the re-arm zone), still (< 15°/s) for ≥ 0.25 s, nothing head-related is busy (Keys: a head gesture holding/active; Aim: pointer speed ≠ 0; Snake: any axis holding or not armed), no head output fired in the last 0.3 s (Snake: 0.8 s after a turn, so it can't drift toward a turn the head is still holding or returning from), input isn't blocked, and a face is visible. Ease rate = dt / follow time. ON by default in every mode; per-mode switch + Follow time slider (0.3–8 s, default 1.5 s since 2026-10-19, was 2 s) saved in UserDefaults key `floatingCenter.v1`; on first launch the old Snake auto-recenter choice is migrated. Calibration and Recenter set the anchor; the Direction pad draws the floating center as a purple ring (with the trigger box) relative to the anchor's grey cross.
- **Recenter (all modes):** button / R in the window / ⌃⌥⌘R from any app (Carbon hotkey id 2, plays "Morse"). Sets neutral head angles to the current smoothed pose instantly (mouth/eyebrow neutral unchanged), releases everything, re-arms Snake. Recalibrate (C) is still the full 3-second calibration.
- **Smoothing:** One Euro filter (minCutoff 2.5 Hz; beta 0.1 for head degrees, 0.03 for expression %).
- **Calibration:** 3 s of face-visible time at launch; median of samples (head + mouth + eyebrows); jitter shown per value with a warning when it's over a third of that gesture's press threshold. C (window focused) or button recalibrates. Input blocked while calibrating.
- **Kill switch:** ⌃⌥⌘K (Control+Option+Command+K), Carbon `RegisterEventHotKey` (works in any app, needs no permission). Plays "Tink" (on) / "Pop" (off). Control starts ON after the first calibration (`Config.Safety.startWithControlOn`).
- **Safety:** everything (keys, mouse button, pointer movement) released/stopped on control off, face lost > 200 ms (pointer stops at once), mouth/eyebrows unreadable > 200 ms (their outputs only), camera frames stopping (watchdog), mode switch, recalibration, Accessibility revoked (polled every 0.5 s), quit/Ctrl+C/Terminal closed. After any release gestures need a return to neutral before firing again. Crash / `kill -9` can't be caught: tap the real key.
- **Input events:** `CGEvent` from a `.hidSystemState` source, posted at `.cghidEventTap`, modifier flags cleared (arrows get fn + numeric pad). Held keys don't auto-repeat (expected; games track held state).
- **Camera:** fastest fps up to 60 (most built-in Mac cameras: 30), resolution closest to 640x480 within 480x360–1280 wide, frame rate locked (no low-light slowdown).
- **Latency shown:** camera capture timestamp → key/click event sent (plus Vision time incl. landmarks, total processing, camera delay, FPS, dropped frames).
- **Permissions:** when run via `swift run` they belong to Terminal (or iTerm/VS Code). The window shows step-by-step instructions + buttons to System Settings.

## Progress Log
- 2026-10-18: Project planned. GitHub repo created (private; made public later the same day so it can be cloned without a GitHub login). Decided: downloadable app + website with browser demo. Clarified: mainly for disabled gamers, fully face-controlled (head + expressions + head aiming), must work in fast games, native Swift, Apple Silicon, no voice. No code yet.
- 2026-10-18: **Phase 1 prototype built** (code only; compiles on macOS CI, not yet run on a real Mac). SwiftPM app with SwiftUI debug window: camera preview, pitch/yaw/roll (raw + vs. neutral), calibration status, threshold bar with press/release lines, "% to trigger", Space held, control ON/OFF, FPS, Vision/processing time, frame→key latency, recent safety events, permission instructions. Gesture: tilt head up = hold Space. Added README.md (setup, permissions, kill switch, tuning), TESTING.md (TextEdit → Chrome dino → Minecraft checklist + report template), .gitignore, and the GitHub Actions macOS build.

- 2026-10-18: Added the owner's ideas backlog, long-term vision, and competitor update (PlayAbility, GameFace archived) to this brief. Core decisions unchanged (Mac first, no voice for now). Nothing built from the backlog yet.

- 2026-10-18: Owner ran Phase 1 on his Mac: "looks okay." Decided directions are always from the player's point of view (mirror-corrected). Detailed TESTING.md numbers not reported yet.

- 2026-10-18: Owner chose **Google Snake** (google.com search "snake") as the first real game to test after Phase 2. Needs head up/down/left/right → arrow keys, 4 directions.

- 2026-10-19: **Phase 2 built** (code only; compiles on macOS CI, not yet run on a real Mac). Added: player-perspective directions with mirror correction, Direction pad and `Config.Directions` flips; turn left/right = hold A/D; Vision face landmarks for mouth open (= hold left mouse) and eyebrow raise (= hold E), measured relative to the calibrated neutral face; head-to-mouse aiming (deadzone, response curve, sensitivity slider, smoothing, 120 Hz output) behind an Aim mode; Snake mode (tap arrows, return to center between turns); Keys / Aim / Snake picker; gesture table showing every gesture's live value, thresholds and firing state; expression-lost safety rule; mouse button and movement included in all safety releases. `KeyboardOutput` replaced by `VirtualInput`. README and TESTING.md rewritten for Phase 2 (with a Snake section).

- 2026-10-18: Owner tested Phase 2 in **Google Snake**: very hard to play. All 4 directions: have to move head too far, feels laggy, gestures barely trigger, and after the first turn it almost never fires again (~1 success in 10 tries), so turns can't be chained. Likely causes: Snake re-arm requires BOTH axes within 5° of neutral (too strict, and neutral posture drifts), 10° press threshold too big, smoothing adds lag. Fix requested next session (see Next Steps).

- 2026-10-19: **Snake mode fixed (code only; compiles on macOS CI, not yet tested on the Mac).** New `SnakeController`: per-axis re-arm (only the axis that fired, at 45% of the press threshold by default), flick (head-speed) triggering, reverse-flick block, 100 ms minimum between turns. Press threshold 5°, hold 30 ms, Snake-only lighter smoothing on raw angles, landmarks skipped in Snake. Drift correction while resting near center. Recenter button / R / ⌃⌥⌘R (all modes). Snake tuning panel: live sliders (press, re-arm, hold, smoothing, flick speed, auto-recenter) saved between launches, Copy button for the values, "Right now" per-axis status explaining why a turn isn't firing, last turn + frame→key latency + turn counts. TESTING.md has a Snake tuning guide.

- 2026-10-18: Owner retested Snake after the fixes: "much better," but still a little buggy. Requested a floating center that follows the head. Keep improving Snake in small steps.

- 2026-10-18: Owner decided the floating center should be the default for ALL games/modes, not just Snake.

- 2026-10-19: **Floating center + Snake round 3 built (code only; compiles on macOS CI, not yet tested on the Mac).** Floating center in all modes (on by default, per-mode switch, Follow time slider, saved, migrated from Snake auto-recenter), never moving while a direction is firing/held/re-arming or the pointer is moving; shown as a purple ring on the Direction pad and in a Floating center box. Snake: Turn log (fired turns with latency, blocked turns with reasons), bounce-back block now covers position turns too (0.35 s), same-direction cooldown (0.25 s) against double turns, earlier flick firing on motion onset, flick minimum 30% of press; saved slider values load tolerantly. TESTING.md: new section 1b (floating center checks) and Snake turn-log checks.

- 2026-10-19: Owner tested round 3 (floating center + turn log) in Google Snake: works sometimes, but quick back-to-back turns often don't fire at all (no wrong-direction or late turns reported). Didn't check the Turn log yet. Likely cause: the safety blocks (bounce-back 0.35 s opposite-direction block, 0.25 s same-direction cooldown, 0.10 s min interval) eat real fast turns, e.g. right → down → left quickly (left is blocked as a "bounce" of right). Google Snake itself ignores 180° reversals and repeated directions, so most of these blocks aren't needed in Snake mode.

- 2026-10-19: **Snake round 4 built (code only; compiles on macOS CI, not yet tested on the Mac).** Confirmed the cause in code: in right → down → left, the left/right axis re-arms while swinging from right to left and the left turn arrives within 0.35 s, so the bounce-back block ate it; the 0.10 s min interval also DROPPED quick second turns, and only one axis could fire per frame. Fixes: bounce-back and double-turn blocks off by default (switches in the Snake panel); min time between turns is a slider (default 45 ms) that delays instead of drops; both axes can fire in one frame (diagonals send both turns, spaced); floating center in Snake follows only within half the re-arm zone and waits 0.8 s after a turn; Turn log shows blocked/not-sent turns in red. Saved slider values kept (new fields default in).

- 2026-10-19: Owner tested round 4: fast turns now go through, but occasional **unwanted extra turns**. Screenshot of the Turn log showed 5 turns in 0.6 s (RIGHT, UP, LEFT, RIGHT, DOWN), two pairs only one camera frame apart on different axes (UP→LEFT, RIGHT→DOWN), and the head going 13–25° for a 5° threshold. The two red lines were false "not re-armed yet" alarms (head still moving out 300 ms after the turn). Values: press 5°, re-arm 45%, smoothing 30%, flick 70°/s, min gap 45 ms, blocks off.

- 2026-10-19: **Snake round 5 built (code only; compiles on macOS CI, not yet tested on the Mac).** Likely causes: big fast moves swing back past center (a small opposite flick fires), and a fast move on one axis leaks into the other (flicks fire at only 1.5°). Added the extra-turn guard (on by default, toggle): during a swing-back or while the other axis moves faster, a flick must reach the full press threshold; small ones that stop short are logged in orange. Turn log adds "head went to N°" per turn; false "not re-armed yet" alarms removed. Checked with a Python port of the axis logic on simulated head motion: small swing-backs and leaks are now ignored; right → down → left, a U-turn (right, up, left), a diagonal and a deliberate left → right still fire every turn with no added delay at 30 fps.

- 2026-10-19: Owner: **Google Snake "looks great"** after the latest fixes. Snake milestone done. Next: lock in his slider values as defaults, record a demo clip, then Phase 3.

- 2026-10-19: Owner doesn't have Minecraft on his Mac. Phase 3 (move vs. aim) will be tested in **Minecraft Classic in the browser** (classic.minecraft.net, free, official Mojang, WASD + mouse look + Space jump) instead.

- 2026-10-19: Owner asked to make the tuned slider values the Snake defaults (read from the owner's screenshot; the pasted Copy text was missing): press 8.5°, re-arm 45%, hold 40 ms, smoothing 25%, flick 80°/s, min gap 45 ms, extra-turn guard on, blocks off; Follow time 1.5 s. Asked for Phase 3 in Minecraft Classic with three switchable options.

- 2026-10-19: **Phase 3 options built (code only; compiles on macOS CI, not yet tested on the Mac).** New Minecraft mode with a head option picker: 1 Face moves, head aims (mouth = W, eyebrows = Space); 2 Mode switch (tilt toward a shoulder flips MOVE W/A/S/D ↔ AIM, sounds, pause while tilted, Switch now button); 3 Split zones (aim, plus W/A/S/D past the walk zone). Engine bindings/thresholds are now computed live per mode/option/job. Minecraft panel, always-on-top overlay label, floating center + safety rules in every option, closing the debug window quits even with the overlay up. Snake and Follow time defaults updated. TESTING.md section 8 (same course for every option + report), README Minecraft section.

- 2026-10-21: Owner wants a **Scroll mode for YouTube** next (before Phase 3): scroll with his head. Planned as two sub-options: smooth page scrolling (head tilt = scroll wheel, speed by angle) and Shorts mode (one head flick = next/previous Short via arrow keys, reusing Snake's tap logic). Phase 3 waits until after this.

- 2026-10-21: **Scroll mode built (owner asleep; code only; compiles on macOS CI, not yet tested on the Mac).** Smooth scroll (tilt = real scroll-wheel events, deadzone + speed sliders, eased acceleration, Reverse switch) and Shorts (one nod = ↓/↑ via Snake's tap logic with its own saved sliders, blocks on). Mouth = Space play/pause (0.3 s hold, switchable). Engine: Snake's controller is now `taps`, shared by Snake and Shorts. TESTING.md section 9 (YouTube), README Scroll section.

## Next Steps
- Owner tests **Scroll mode on YouTube** (TESTING.md 9): smooth scrolling (best Deadzone/Speed, direction, reading comfort, accidental scrolling), Shorts (N nods → N videos, no going back), mouth play/pause.
- Owner tests the three **Minecraft** options (TESTING.md 8) in full-screen Chrome on classic.minecraft.net and picks one. Report per option: look/walk/overall 1–5, accidental switches/walking, best slider values, worst part, and whether the view turns in the browser at all (pointer-lock deltas) and whether the overlay shows over full-screen Chrome.
- Then refine the chosen option (and decide whether option 1 needs a third expression, e.g. smile = click; ask first). Right click (place block) has no gesture yet.
- Owner tests the **floating center** (TESTING.md 1b) in Keys/Aim: held A/D/Space must never release by itself; nothing may fire after resting in a new spot.
- Record a Snake demo clip (owner).
- Still open from Phase 2: Direction pad check (yaw sign), mouth/eyebrow reliability numbers (Vision vs. MediaPipe decision), Aim mode feel.
