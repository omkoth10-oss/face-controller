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

### Open design problem: head does two jobs
Head movement is wanted for both movement keys and mouse aiming. These conflict. Options to explore and test:
- Head = aim, facial expressions = movement/actions.
- Mode switch gesture (e.g., hold a gesture to swap head between "move" and "aim").
- Per-game presets choose which mapping fits.
Decide by prototyping and testing, not guessing.

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

## Code map (Phase 1)
All code is in `Sources/FaceController/`:
- `Support/Config.swift`: **every tunable number** (thresholds, timings, camera, smoothing, kill-switch key).
- `Camera/CameraManager.swift`: AVFoundation capture, picks fastest fps (≤60) then size closest to 640x480, drops late frames.
- `Tracking/HeadPoseTracker.swift`: Vision → pitch/yaw/roll. `Tracking/OneEuroFilter.swift`: smoothing.
- `Calibration/Calibrator.swift`: neutral pose = median of 3 s of face-visible samples.
- `Gestures/ThresholdGesture.swift`: hysteresis + hold time → press/release.
- `Input/KeyboardOutput.swift`: CGEvent keys; tracks held keys; "block reasons" (control off, calibrating, no permission, quitting) release everything and refuse presses.
- `Engine/ControlEngine.swift`: the tight loop on one serial queue (camera → Vision → gesture → key), face-lost rule, 50 ms watchdog, snapshots for the UI.
- `Safety/`: `GlobalHotKey.swift` (Carbon kill switch), `ExitGuard.swift` (atexit + SIGINT/SIGTERM/SIGHUP/SIGQUIT release keys), `Permissions.swift`.
- `App/`: `FaceControllerApp.swift` (@main, activation policy), `AppController.swift` (wiring, permissions, kill switch).
- `UI/`: `DebugView.swift`, `CameraPreview.swift`.

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
2. **Core gestures + aiming** (4–6 sessions): turn left/right, mouth open, eyebrow raise, head-to-mouse aim, false-trigger fixes, latency measurement.
3. **Solve head move-vs-aim** (2–3 sessions): prototype options, test, pick one.
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

## Phase 1 decisions and starting settings (2026-10-18, untested on hardware)
- **Head angles:** `VNDetectFaceRectanglesRequest` revision 3 (fastest Vision face request; continuous pitch/yaw/roll). Landmarks wait for Phase 2 expressions.
- **Pitch direction is unverified:** Apple doesn't document the sign. Code assumes tilting UP makes Vision pitch NEGATIVE. `Config.TiltUp.flipDirection = true` swaps it. First thing to confirm in testing.
- **Tilt up = hold Space:** press at 10°, release below 6°, 80 ms hold. Release is immediate.
- **Smoothing:** One Euro filter (minCutoff 2.5 Hz, beta 0.1): heavy when still, near zero when moving fast.
- **Calibration:** 3 s of face-visible time at launch; median of samples; C (window focused) or button recalibrates. Presses blocked while calibrating.
- **Kill switch:** ⌃⌥⌘K (Control+Option+Command+K), Carbon `RegisterEventHotKey` (works in any app, needs no permission). Plays "Tink" (on) / "Pop" (off). Control starts ON after the first calibration (`Config.Safety.startWithControlOn`).
- **Safety:** keys released on control off, face lost > 200 ms, camera frames stopping (watchdog), Accessibility revoked (polled every 0.5 s), quit/Ctrl+C/Terminal closed. After any release the gesture needs a return to neutral before it can fire again. Crash / `kill -9` can't be caught: tap real Space.
- **Key events:** `CGEvent` from a `.hidSystemState` source, posted at `.cghidEventTap`, modifier flags cleared. Held keys don't auto-repeat (expected; games track held state).
- **Camera:** fastest fps up to 60 (most built-in Mac cameras: 30), resolution closest to 640x480 within 480x360–1280 wide, frame rate locked (no low-light slowdown).
- **Latency shown:** camera capture timestamp → key event sent (plus Vision time, total processing, camera delay, FPS, dropped frames).
- **Permissions:** when run via `swift run` they belong to Terminal (or iTerm/VS Code). The window shows step-by-step instructions + buttons to System Settings.

## Progress Log
- 2026-10-18: Project planned. GitHub repo created (private). Decided: downloadable app + website with browser demo. Clarified: mainly for disabled gamers, fully face-controlled (head + expressions + head aiming), must work in fast games, native Swift, Apple Silicon, no voice. No code yet.
- 2026-10-18: **Phase 1 prototype built** (code only; compiles on macOS CI, not yet run on a real Mac). SwiftPM app with SwiftUI debug window: camera preview, pitch/yaw/roll (raw + vs. neutral), calibration status, threshold bar with press/release lines, "% to trigger", Space held, control ON/OFF, FPS, Vision/processing time, frame→key latency, recent safety events, permission instructions. Gesture: tilt head up = hold Space. Added README.md (setup, permissions, kill switch, tuning), TESTING.md (TextEdit → Chrome dino → Minecraft checklist + report template), .gitignore, and the GitHub Actions macOS build.

- 2026-10-18: Added the owner's ideas backlog, long-term vision, and competitor update (PlayAbility, GameFace archived) to this brief. Core decisions unchanged (Mac first, no voice for now). Nothing built from the backlog yet.

## Next Steps
- Owner runs Phase 1 on the Mac and works through TESTING.md, then pastes back the report (first: does "Tilt up" go positive when tilting up? camera fps, processing time, frame→key latency, false triggers when talking/laughing).
- Tune `Config.swift` from those numbers (thresholds, hold time, smoothing, pitch direction).
- Then start Phase 2: turn left/right, mouth open, eyebrow raise, head-to-mouse aim, false-trigger fixes, latency work.
