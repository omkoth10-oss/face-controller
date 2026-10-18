# Phase 1 testing checklist

Work through these in order. Each step builds on the one before. Write down the
numbers marked **📋 Report**; at the end there's a template to paste back to Claude.

Before you start:

```bash
cd face-controller
git pull
swift run
```

Sit how you normally would to play, with normal room lighting.

---

## 0. Setup and first look (5 min)

- [ ] The debug window opens and has a Dock icon.
- [ ] macOS asked for **Camera** access (for Terminal) and you allowed it.
- [ ] macOS asked for **Accessibility** access and you turned on Terminal in
      System Settings. The red "Accessibility access is off" box disappears within
      about a second.
- [ ] The camera preview shows your face (mirrored like a mirror).
- [ ] The overlay says **"Look straight at the camera"** and fills up over
      ~3 seconds, then disappears. Calibration says **Calibrated ✓**.
- [ ] **Face:** says "Detected".
- [ ] **Direction check:** tilt your head UP (chin up). The **Tilt up** number
      should go **positive** and the bar should fill.
      ⚠️ If it goes **negative**: quit, set `TiltUp.flipDirection = true` in
      `Sources/FaceController/Support/Config.swift`, and run again.
- [ ] Press **C** in the debug window: calibration runs again.

📋 **Report:**
- Camera line under the preview (name, resolution, fps)
- Camera FPS, Vision time / frame, Total processing / frame, Camera delay
- Calibration jitter (the "±" number)
- With your head still and relaxed: how much does **Tilt up** wobble? (e.g. "between −1 and +1°")
- Comfortable tilt-up: what **Tilt up** number do you reach with a small, comfortable chin-up? A big one?

## 1. TextEdit: does Space arrive? (5 min)

Open TextEdit, make a new document, and click in it so the cursor blinks.

- [ ] Tilt head up → **one space** appears, and the debug window shows **SPACE HELD**.
      (Only one space even if you keep holding: the app holds the key down but
      macOS doesn't auto-repeat simulated keys. That's expected and fine for games.)
- [ ] Return to neutral → **Space released**.
- [ ] Do it 20 times in a row at a normal pace. Count the spaces.
- [ ] Hover right around the red line for a few seconds. Space should NOT flicker
      on/off (you should get at most 1–2 spaces, not a burst).
- [ ] **Kill switch:** press **⌃⌥⌘K** (Control + Option + Command + K). You hear a
      "pop", Control shows **OFF**. Tilting up does nothing. Press it again: "tink",
      Control is **ON** again.
- [ ] Hold your head tilted up (Space held), then press **⌃⌥⌘K**. Space must
      release immediately.

📋 **Report:** spaces typed out of 20 tilts; any flicker; kill switch worked (yes/no).

## 2. False triggers: talking, laughing, looking around (10 min)

Stay in TextEdit with control ON. Watch whether spaces appear when they shouldn't.

- [ ] **Talk** normally for 1 minute (read something out loud). Count accidental spaces.
- [ ] **Laugh** a few times (a real laugh, head moving). Count accidental spaces.
- [ ] **Nod** "yes" a few times like in conversation. Count accidental spaces.
- [ ] **Look down** at the keyboard, then back up at the screen. Count accidental spaces.
- [ ] **Look away** to the side / turn around so the camera can't see your face
      while holding Space (tilt up, then turn away). Space should release within
      ~0.2 s and the event list should say "face lost". When you come back,
      Space should NOT press again until you've returned to neutral.
- [ ] **Cover the camera** with your hand while Space is held: it should release.
- [ ] Lean back / slouch / move closer to the screen without tilting your head.
      Any accidental spaces? (If yes, try recalibrating with C in your new position.)

📋 **Report:** accidental spaces for talking / laughing / nodding / looking down;
did face-lost release work; anything else that triggered by accident.

## 3. Chrome dino game (10 min)

Open Chrome and go to **chrome://dino** (or turn off Wi-Fi to get it). Click the
page once so it has focus.

- [ ] Tilt up to start the game and to jump.
- [ ] Play 5 rounds. Note your best score.
- [ ] Does the jump feel instant, or late? Do you die because the jump came late?
- [ ] Do you get accidental jumps?
- [ ] After a few rounds, check the debug window **Speed** box.

📋 **Report:** best score; "feels instant / slightly late / too late"; Camera FPS,
Total processing / frame, **Frame → key event (avg)**, dropped frames.

## 4. Minecraft jumping (10 min)

Java or Bedrock edition, a creative or peaceful world.

- [ ] Tilt up → your character jumps. Keep your head tilted → keeps jumping
      (holding Space). Return to neutral → stops.
- [ ] Walk with your hands (W) and jump with your face over a few blocks.
- [ ] In creative mode: double-tap Space with two quick tilts toggles flying. Does it work?
- [ ] Press **Esc** (game menu) and **⌃⌥⌘K** while in full screen: does the kill
      switch work in full screen (listen for the sound)?
- [ ] Alt-tab / Cmd-tab out of Minecraft while Space is held. Nothing should stay stuck.

📋 **Report:** jumping works (yes/no); flying double-tap (yes/no); kill switch in full screen (yes/no); any stuck keys.

## 5. Stuck-key checks (5 min)

For each one, tilt up so Space is held first, then:

- [ ] Press **Cmd+Q** in the debug window → app quits, Space is released.
- [ ] Run again, hold Space, press **Ctrl+C** in Terminal → app quits, Space is released.
- [ ] Run again, hold Space, close the **Terminal window** → app quits, Space is released.
- [ ] Run again, hold Space, turn **off** Terminal's Accessibility permission in
      System Settings → within ~1 s the debug window shows the red box and Space is released.

How to tell Space is released after quitting: open TextEdit and press a letter
key; if Space were stuck, the system would behave oddly (e.g. Space-related
shortcuts). If anything ever stays stuck, tap the real Space bar once.

📋 **Report:** any case where Space stayed stuck.

## 6. Comfort (ongoing)

- [ ] After 10 minutes, is your neck tired? Is the tilt amount comfortable?
- [ ] Did you need to recalibrate during the session? Why (moved chair, slouched)?

---

## Report template (copy, fill in, paste back to Claude)

```
Mac model / macOS version:
Camera line (name, resolution, fps):
Direction check: Tilt up went positive when tilting up? (yes / needed flipDirection)

Speed:
  Camera FPS:
  Vision time / frame:
  Total processing / frame (and max):
  Camera delay:
  Frame -> key event (avg):
  Dropped frames (after ~5 min):

Calibration jitter:
Tilt-up wobble when still:
Comfortable tilt-up reaches about:   ° (big tilt:   °)

TextEdit: spaces typed out of 20 tilts:     flicker? 
Kill switch works: (yes/no)   in full screen: (yes/no)
Accidental spaces — talking:   laughing:   nodding:   looking down:
Face lost released Space: (yes/no)
Dino: best score:    feel (instant / slightly late / too late):
Minecraft: jump works:   hold-to-keep-jumping:   flying double-tap:
Any stuck keys? (what were you doing):

What felt worst / what made you want to stop using it:
Anything else:
```
