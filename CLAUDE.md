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
- **No polished, gaming-first, Mac-friendly, fully face-controlled app exists.**

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
1. **Swift prototype** (2–3 sessions): camera + Vision tracking, head tilt up = hold Space, calibration, debug window. Test in TextEdit → Chrome dino game → Minecraft.
2. **Core gestures + aiming** (4–6 sessions): turn left/right, mouth open, eyebrow raise, head-to-mouse aim, false-trigger fixes, latency measurement.
3. **Solve head move-vs-aim** (2–3 sessions): prototype options, test, pick one.
4. **Settings UI + mapping + onboarding** (3–5 sessions).
5. **Presets, speed mode, testing across games, bug fixes** (3–6 sessions).
6. **Release** (1–3 sessions): GitHub release, README, demo video, website + browser demo, Reddit (r/macgaming, r/disabledgamers, r/accessibility), Product Hunt.
7. **Outreach:** send demo video to AbleGamers, ask what's missing and for testers.

Key question for every tester: **"What made you stop using it?"**

## Rules for Claude
- Use whatever level of complexity the project actually needs, but keep it well-organized and commented, and briefly explain new or tricky parts in plain language so I understand how it works.
- Reliability and speed over new features.
- Don't add features outside this brief without asking.
- **After every change** (code, decision, or plan update): update this file to match, then commit and push to GitHub so cloud and local sessions always stay in sync.
- Note: cloud sessions can't use the webcam. Write code in the cloud; the owner tests on his Mac.

## Progress Log
- 2026-10-18: Project planned. GitHub repo created (private). Decided: downloadable app + website with browser demo. Clarified: mainly for disabled gamers, fully face-controlled (head + expressions + head aiming), must work in fast games, native Swift, Apple Silicon, no voice. No code yet.

## Next Steps
- Build the Phase 1 Swift prototype.
