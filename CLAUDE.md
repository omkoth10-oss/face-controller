# Face Controller — Project Brief

> Claude: read this at the start of every session. At the end of every session, update the **Progress Log** and **Next Steps** sections at the bottom.

## The idea
A free Mac app that turns your webcam into a game controller. You move your head or make facial expressions (tilt head up, raise eyebrows, open mouth) and the app presses keys or moves the mouse. It sends real-looking keyboard/mouse input at the OS level, so it works with almost any game without the game needing to support it.

Working name: TBD (placeholder "Face Controller").

## Who it's for
1. **Disabled gamers** with limited hand/arm use but good head/face control. Current options (adaptive controllers, QuadStick, eye trackers) cost $90–$500+. This needs only a webcam and is free.
2. **Regular gamers** who want extra inputs in a **hybrid mode**: aim with the mouse, use quick face gestures for jump, reload, or weapon switch.

## Why it's worth building (the gap)
- Google Project Gameface: Windows only, head mostly controls the mouse, clunky setup, accessibility tool rather than gaming product.
- SensePilot: PC, not Mac.
- macOS built-in Head Pointer: cursor/click only, not built for game keybinds.
- Hawkeye Access: needs an iPhone TrueDepth camera, accessibility-focused.
- GitHub hobby projects: code demos, not installable apps.
- **No polished, gaming-first, Mac-friendly app with per-game presets exists.**

## Goals
- Fun learning project + college application project.
- Free and open source (GitHub), optional donation link. Impact over money.
- Real users matter more than features. Target: ~1,000 downloads year one, 50+ real active users, 1+ strong user story.
- Get feedback from disabled gamers (AbleGamers, possibly their Player Panels playtesting program).

## Tech plan
- **Prototype:** Python 3.11/3.12, MediaPipe Face Landmarker, OpenCV, pynput. One file + requirements.txt.
- **v1 app:** Native Mac app (Swift + Apple Vision, or keep MediaPipe), menu bar app with settings UI.
- macOS permissions needed: Camera, Accessibility, Input Monitoring. Setup screen must guide users clearly.
- Later: signing/notarization ($99/yr Apple Developer) to avoid "unidentified developer" warnings. GitHub release first.

## Features (priority order)
**Must-haves**
1. No false triggers: short hold time before firing, dead zones for small movements.
2. One-click calibration ("look straight for 3 seconds"), recalibrate anytime.
3. Pause gesture (e.g., eyes closed 2 sec) so talking or laughing doesn't trigger actions.
4. Live feedback overlay: active key + how close each gesture is to triggering.
5. Simple mapping screen: pick gesture, press key, done.

**Make people want it**
6. Ready-made game presets: Minecraft, Roblox, Geometry Dash, browser games.
7. Hold / tap / toggle modes per gesture (toggle reduces neck strain).
8. Head-to-mouse aiming with adjustable smoothing.
9. Sensitivity slider per gesture.
10. Hybrid mode: works alongside mouse, keyboard, foot pedal, or voice.

**Extras**
11. Small-gesture mode for limited movement.
12. Practice mini-game to learn gestures (great for demo video).
13. Export/import profiles, community sharing.
14. Fatigue/break reminders.
15. Works in low light and with glasses.

## Speed mode (fast games / shooters)
- Use 60 fps webcam if available; run tracking at low resolution.
- Short hold time (~50 ms) in speed mode vs ~200 ms default.
- Prefer tiny fast gestures (eyebrow raise, mouth open) over big head turns for jump/shoot.
- Detect motion onset (quick flicks), not just final position.
- Single tight loop: camera → tracking → key press, no extra waits.
- Honest limit: won't match mouse/keyboard in competitive shooters. Best as hybrid mode.
- Competitive games with anti-cheat (e.g., Valorant) may block simulated input. Focus on casual and single-player games.

## Roadmap
1. **Prototype** (1–2 sessions): head tilt up = hold Space, calibration, debug window. Test in TextEdit → Chrome dino game → Minecraft.
2. **Core gestures** (3–6 sessions): left/right = A/D, mouth open = click, sensitivity, false-trigger fixes.
3. **Settings UI + mapping** (3–5 sessions).
4. **Real Mac app** (4–8 sessions).
5. **Presets, testing across games, bug fixes** (3–6 sessions).
6. **Release** (1–3 sessions): GitHub release, README, demo video, Reddit (r/macgaming, r/disabledgamers, r/accessibility), Product Hunt.
7. **Outreach:** send demo video to AbleGamers, ask what's missing and for testers.

Key question for every tester: **"What made you stop using it?"**

## Rules for Claude
- Use whatever level of complexity the project actually needs, but keep it well-organized and commented, and briefly explain new or tricky parts in plain language so I understand how it works.
- Reliability over new features.
- Don't add features outside this brief without asking.
- Update this file at the end of each session.

## Progress Log
- 2026-10-18: Project planned. No code yet.

## Next Steps
- Build the Phase 1 prototype.
