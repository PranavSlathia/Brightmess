# Glass Firefly

The wide emerald wing and upright pear wing echo two displays. The amber lantern is their light source. The bug is BRIGHTMESS’s own mascot; Ayrlo’s colourful menu-bar treatment was a reference, not a source asset.

## Packaging

- `BRIGHTMESS.icon` is the editable Apple Icon Composer source. Xcode’s asset compiler produces the layered `Assets.car` and backward-compatible `BRIGHTMESS.icns` in `Compiled/`. The Mini installer ships both before signing; it declares both bundle icon keys.
- `MenuFirefly-master.png` is separate, optically simplified artwork on transparent pixels. Its 96-pixel export ships as `Sources/BrightnessRelay/Resources/FireflyMenu.png`. Both the menu bar and header use original colour, never template tinting. The firefly rests still; only the solar or attention badge changes.
- Regenerate the compiler outputs with a full Xcode selected: `scripts/rebuild-brand-icons.sh`. Ordinary installs don't require regeneration. `scripts/check-brand-icons.sh docs/brand-icons.png` exercises the real AppKit mark and Icon Services rendering without restarting the receiver.
- `scripts/install-mini.sh --stage-only` creates a signed Mini app under `.build/` without changing the live installation. Pass its printed path as the second argument to `check-brand-icons.sh` to check that app's Icon Services artwork.

## Artwork provenance

Both illustrations were generated with the built-in image generation tool. No screenshots, third-party mascots, or physical device data were embedded.

**App foreground prompt**

Use case: logo-brand. Create a single premium macOS icon foreground asset, on a genuinely transparent background. The character is a friendly jewel-like FIREFLY of LIGHT for BRIGHTMESS, a Mac utility for sending light between two displays. One small rich amber luminous lantern abdomen (the focal point), tiny dark petrol enamel head with two inset dots for eyes, two short sturdy antennae. Two striking broad, asymmetric molten-glass wings fan upward and outward: to viewer left a low wide turquoise / deep emerald glass wing, to viewer right a higher upright pear-chartreuse glass wing, echoing a wide TV and a rotated monitor. Form the wings from plump simple rounded slabs, with a single thick edge bevel and one intentional highlight on each. Amber-peach refracts through the centre. One coherent charismatic sculpture with a bold outline; cozy, precise, a little curious; not an anatomically detailed insect. Slight top/front three-quarter view, nearly frontal, torso centered, fills 86 percent of a square canvas. Realistic luxurious optical glass: jewel depth, rich dark rims; no glitter, no RGB rainbow, no wire-thin legs, no busy patterns. Composition isolated, free-floating object only, no squircle tile, no floor, no background shadow, no gradients outside the object, no text, no letters, no frames, no watermarks. Intended for a 1024-pixel app icon and later a 17-point-high colourful menu-bar emblem, so its silhouette must carry even at that scale.

**Menu optical master prompt** (app foreground supplied as the reference)

Use case: identity-preserve. Create the small-size optical master of this SAME BRIGHTMESS glass firefly for a colourful macOS menu-bar icon. The reference is the identity to KEEP: the squat dark head with two amber eyes, turquoise wide wing on the left, chartreuse upright wing on the right, orange lantern at bottom. Design for only 23×17 points. Make it about 1.3:1 wide, enlarge the face slightly, thicken its two short antennae, trade the fine optical detail for bold enamel-glass lobes and one reflection per wing; let a fine pale sage rim separate its dark head and antennae from black menu bars, and a rich dark forest keyline separate the pale wings from light menu bars. Preserve the charm of blown glass. No background plate, no outline sticker halo, no text, no shadow outside, nothing other than the compact sculpted character. Center the whole, uncropped object on a truly transparent background; eyes, wings and lantern must still separate after reduction. Not a cartoon drawing. Not an app icon container.
