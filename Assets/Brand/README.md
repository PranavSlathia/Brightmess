# Out of Register

A wide TV and an upright monitor share a single lime brightness stripe.
One amber pixel sits just outside the right bezel. The two glass screens
echo this desk; the offset pixel is the “mess.” It is not an error badge.

- **App icon:** `BRIGHTMESS.icon` is the editable Apple Icon Composer source.
  The foreground uses the original approved Out of Register image-generation
  study, padded to a square without stretching it. The compiler outputs in
  `Compiled/` provide the layered macOS artwork and an ICNS fallback.
- **Menu mark:** `Sources/BrightnessRelay/DeskMark.swift` draws an original-colour
  23 × 17 point version using native paths. It needs no runtime image file.
  Solar fallback and receiver attention add distinct shapes above the TV;
  neither obscures the stripe or amber pixel. The header uses the resting mark.
- **Motion:** opening the menu raises the two stripes together, then snaps the
  amber pixel into line. This is a local opening cue, not confirmation of a TV
  command or Air reading. Closing cancels it. Reduce Motion shows the final pose
  immediately; no idle animation or network traffic.

With full Xcode selected, `scripts/rebuild-brand-icons.sh` regenerates the
compiler outputs. Ordinary installs use the checked-in outputs. Run
`scripts/check-brand-icons.sh docs/brand-icons.png` for the native-size proof,
including Icon Services lookup, status cues, closing and Reduce Motion.
`scripts/install-mini.sh --stage-only` produces a signed app without restarting
the receiver. Pass the resulting path as the second argument to the proof script
to verify that particular bundle.
