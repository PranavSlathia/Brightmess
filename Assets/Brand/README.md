# The Brightest Mess

A wink, a crooked grin and one ray that couldn't stay in line. The sun makes the
name's brightness / bright mess wordplay visible. The amber ray is always
part of the mark, never a warning.

- **App icon:** `BRIGHTMESS.icon` is the editable Apple Icon Composer source.
  `Assets/BrightestMess.png` is a transparent render of the hand-drawn AppKit
  paths, informed by a generated concept study. The compiler outputs in
  `Compiled/` provide layered artwork and an ICNS fallback.
- **Menu mark:** `Sources/BrightnessRelay/DeskMark.swift` draws an original-colour
  23 × 17-point version from the same paths. It needs no runtime image file.
  Solar fallback and receiver attention add distinct badges to the right.
  The Source Deck header uses the resting mark.
- **Motion:** opening the menu flicks the runaway ray once. Closing cancels it.
  Reduce Motion shows the resting pose immediately. There is no idle animation
  or network traffic, and the flick doesn't report a TV or Air event.

With full Xcode selected, `scripts/rebuild-brand-icons.sh` regenerates the
foreground and compiler outputs. Ordinary installs use the checked-in outputs.
Run `scripts/check-brand-icons.sh docs/brand-icons.png "" docs/brand-icons-1x.png`
for the native-size proof,
including Icon Services lookup, status cues, closing and Reduce Motion.
`scripts/install-mini.sh --stage-only` produces a signed app without restarting
the receiver. Pass the resulting path as the second argument to the proof script
to verify that particular bundle.
