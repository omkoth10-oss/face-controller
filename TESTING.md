# Phase 2 testing checklist

Work through these in order. Write down the numbers marked **📋 Report**; at the
end there's a template to paste back to Claude.

Before you start:

```bash
cd face-controller
git pull
swift run
```

Sit how you normally would to play, with normal room lighting. The window is
bigger now (three columns). If it doesn't fit your screen, it scrolls.

**Modes** (top of the middle column):

| Mode | Head | Mouth open | Eyebrows raised |
|---|---|---|---|
| **Keys** | up = hold Space, left = hold A, right = hold D | hold left mouse button | hold E |
| **Aim (mouse)** | moves the mouse pointer like a joystick | hold left mouse button | hold E |
| **Snake** | up/down/left/right = one tap of ↑ ↓ ← → | off | off |

Switching mode releases everything. The kill switch **⌃⌥⌘K** still turns all of
it off from any app.

---

## 0. Setup and calibration (3 min)

- [ ] The window opens. Calibration overlay says **"Look straight at the camera,
      mouth closed, eyebrows relaxed"** and finishes after ~3 s.
- [ ] Calibration box says **Calibrated ✓** with mouth and brow numbers (not
      "Couldn't read mouth/eyebrows").
- [ ] No orange "noisy" warnings under Calibration. (If there are, press C and
      hold still.)

📋 **Report:** the Jitter line (pitch, yaw, mouth, brows); Vision time (and
landmarks time); Total processing; Camera FPS.

## 1. Direction check: does the app agree with YOUR head? (2 min)

Look at the **Direction** pad (left column) while you move your head slowly.

- [ ] Turn your head to **your left** → the dot moves **left**, "LEFT" lights up.
- [ ] Turn to **your right** → dot moves **right**, "RIGHT".
- [ ] Tilt **up** (chin up) → dot moves **up**, "UP".
- [ ] Tilt **down** → dot moves **down**, "DOWN".
- [ ] The camera preview looks like a mirror (raise your right hand: it appears on
      the right side of the preview).

⚠️ If left/right is backwards: quit, set `Directions.flipHorizontal = true` in
`Sources/FaceController/Support/Config.swift`, run again. Up/down backwards:
`Directions.flipVertical = true`.

📋 **Report:** all four correct? (or which flip you needed); what the line under
the camera says about frames being mirrored/unmirrored.

## 2. Expression readings: are Vision landmarks good enough? (5 min)

This is the key question for mouth and eyebrows. Watch the **Gestures** table
("Live value") and the **Head and face** box.

- [ ] **Mouth:** relaxed and closed, the Open mouth value sits near **0%**. Open
      your mouth clearly → it goes well past **30%** (red line) and shows **HELD**.
- [ ] **Eyebrows:** relaxed, Raise eyebrows sits near **0%**. Raise them →
      past **8%** and shows **HELD**.
- [ ] **Blink** several times. Does Raise eyebrows jump? (It shouldn't much.)
- [ ] **Smile** big. Does Open mouth or Raise eyebrows jump?
- [ ] **Tilt your head up and down** without moving your eyebrows. Does Raise
      eyebrows change? By how much?
- [ ] **Turn your head left/right.** Does Open mouth change?
- [ ] **Talk** for 30 s. What's the highest Open mouth value you see?

📋 **Report** (rough numbers are fine):
- Open mouth: relaxed ___%, clearly open ___%, while talking up to ___%
- Raise eyebrows: relaxed ___%, raised ___%, while blinking up to ___%,
  while tilting head up ___%
- Did smiling trigger anything?
- Gut feeling: is the eyebrow reading clean or jumpy?

## 3. Keys mode in TextEdit (5 min)

Mode = **Keys**. Open TextEdit, new document, click in it.

- [ ] Tilt up → one **space**. (Held keys don't auto-repeat; that's expected.)
- [ ] Turn left → one **a**. Turn right → one **d**.
- [ ] Raise eyebrows → one **e**.
- [ ] Open mouth → a **click** where the mouse pointer is (the text cursor jumps
      there). Keep it open and move the real mouse: it drags (selects text).
- [ ] The **Held right now** line (Control box) lists exactly what you're holding.
- [ ] Hover right at a red line for a few seconds: nothing should flicker.

📋 **Report:** anything that didn't type / click; any flicker.

## 4. False triggers (5 min)

Stay in TextEdit, Keys mode. Count unwanted characters / clicks.

- [ ] Talk normally for 1 minute (read something aloud).
- [ ] Laugh a few times.
- [ ] Nod "yes" and shake "no" like in conversation.
- [ ] Look down at the keyboard and back up.
- [ ] Blink a lot, smile, frown.

📋 **Report:** unwanted space / a / d / e / clicks for each activity.

## 5. Safety (5 min)

- [ ] Hold a turn (A held), press **⌃⌥⌘K**: "pop", Control OFF, A released.
      Press again: "tink", ON. Nothing fires until you return to neutral.
- [ ] Hold your mouth open (left button held), turn away from the camera:
      released within ~0.2 s; Recent events says "face lost".
- [ ] Hold A, then switch the Mode picker: everything released.
- [ ] Hold A, then Cmd+Q (or Ctrl+C in Terminal): nothing stays stuck.
- [ ] Aim mode: turn your head so the pointer moves, then cover the camera → the
      pointer stops immediately.

📋 **Report:** anything that stayed held or kept moving.

## 6. Aim mode: head moves the mouse (10 min)

Mode = **Aim (mouse)**. Start on the desktop.

- [ ] Look straight: the pointer does **not** drift (deadzone).
- [ ] Turn slightly past neutral → pointer moves slowly. Turn further → faster.
- [ ] Turn left → pointer goes **left**; tilt up → pointer goes **up**.
- [ ] Try the **Sensitivity** slider (right column): find the value that feels best.
- [ ] Put the pointer on small targets (e.g. Dock icons) using only your head.
- [ ] Open mouth to click a Dock icon (aim + click with your face only).
- [ ] **In a game** (e.g. Minecraft, in a world, pointer locked): does turning
      your head turn the camera? Does mouth-open attack/mine?
- [ ] Press ⌃⌥⌘K while aiming: the pointer stops.

📋 **Report:** best sensitivity; does it drift when still?; too slow / too fast
near the center; did it work in a game (which); jittery or smooth?

## 7. Google Snake (10 min)

1. In Chrome, search Google for **snake** and click **Play** on the Snake game.
2. In the debug window, set Mode = **Snake**. (Calibrate again with C if you moved.)
3. Click the Snake game once so it has keyboard focus, keep your head centered.

- [ ] Turn your head left → the snake turns **left** (one turn, not several).
- [ ] Right, up, down each give **one** turn in the right direction.
- [ ] After a turn, nothing else fires until your head comes back to the center
      (the Mode box shows "bring your head back to the center"). Then the next
      turn works.
- [ ] Quick moves: turn left and immediately back. Does it register?
- [ ] Play 5 games. Best score?

If turns feel late, lower `Snake.holdTime` (e.g. 0.03) or `Snake.pressDegrees`
(e.g. 8). If you get double turns (often from overshooting the center on the
way back), raise `Snake.pressDegrees` (e.g. 12) or lower `Snake.neutralDegrees`
(e.g. 4) so "center" is stricter.

📋 **Report:** best score; missed turns?; double turns?; wrong-direction turns?;
does returning to center feel natural or slow?

## 8. Quick game check (optional, 5 min)

- [ ] **Chrome dino** (chrome://dino), Keys mode: still jumps with tilt up.
- [ ] **Minecraft**, Keys mode: turn left/right strafes (A/D), tilt up jumps,
      mouth open attacks, eyebrows open the inventory (E).

---

## Report template (copy, fill in, paste back to Claude)

```
Mac / macOS / camera line:
Frames line under the camera (mirrored / unmirrored):

Direction pad: left __ right __ up __ down __ (correct? flips needed?)

Speed: Camera FPS __  Vision __ ms (landmarks __ ms)  Processing __ ms (max __)
       Frame -> key/click avg __ ms   Dropped frames __

Calibration jitter: pitch ±__  yaw ±__  mouth ±__%  brows ±__%

Mouth: relaxed __%  open __%  talking up to __%
Eyebrows: relaxed __%  raised __%  blinking up to __%  head tilted up __%
Smiling triggered: 
Eyebrow reading clean or jumpy:

TextEdit (Keys): space __ a __ d __ e __ click __ (all worked?)  flicker?
False triggers — talking:  laughing:  nodding:  looking down:  blinking/smiling:

Safety: kill switch __  face lost __  mode switch __  quit __  aim stops __

Aim: best sensitivity __  drift when still? __  feel near center __
     worked in a game? (which) __  smooth or jittery __

Snake: best score __  missed turns __  double turns __  wrong direction __
       return-to-center feel __

What felt worst / what made you want to stop using it:
Anything else:
```
