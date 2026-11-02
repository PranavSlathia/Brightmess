---
name: BRIGHTMESS
description: A native Mac source deck for TV inputs, individual windows and display levels.
colors:
  forest: "#153D2F"
  cream: "#F4F9E9"
  pear: "#DDEBBA"
  leaf: "#C5ED70"
  ground-light: "#F0F3E8"
  ground-dark: "#192C24"
  ink-light: "#153D2E"
  ink-dark: "#F0F4DF"
  muted-light: "#3D574A"
  muted-dark: "#C0CEBB"
  rule-light: "#A0B09A"
  rule-dark: "#576E60"
  shelf-light: "#E4EDCF"
  shelf-dark: "#243D30"
  button-light: "#F6F8ED"
  button-dark: "#2C4436"
  accent-light: "#204834"
  accent-dark: "#D4E6B5"
typography:
  headline:
    fontFamily: "system-ui, sans-serif"
    fontSize: "27px"
    fontWeight: 700
    letterSpacing: "-0.9px"
  source:
    fontFamily: "system-ui, sans-serif"
    fontSize: "19px"
    fontWeight: 700
    letterSpacing: "-0.4px"
  section:
    fontFamily: "system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 700
  device:
    fontFamily: "system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 700
  imprint:
    fontFamily: "system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    letterSpacing: "0.7px"
  route:
    fontFamily: "system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
rounded:
  source: "8px"
  window: "6px"
spacing:
  tile: "5px"
  key: "9px"
  levels: "12px"
  gutter: "16px"
components:
  status-strip:
    backgroundColor: "{colors.forest}"
    textColor: "{colors.cream}"
    height: "36px"
    typography: "{typography.imprint}"
  source-key:
    backgroundColor: "{colors.pear}"
    textColor: "{colors.forest}"
    rounded: "{rounded.source}"
    padding: "9px"
    height: "99px"
    typography: "{typography.source}"
  window-tile:
    backgroundColor: "{colors.button-light}"
    textColor: "{colors.ink-light}"
    width: "135px"
    height: "37px"
    rounded: "{rounded.window}"
  window-tile-dark:
    backgroundColor: "{colors.button-dark}"
    textColor: "{colors.ink-dark}"
    width: "135px"
    height: "37px"
    rounded: "{rounded.window}"
  display-glyph:
    width: "27px"
    height: "25px"
  footer:
    padding: "11px 16px"
    backgroundColor: "{colors.ground-light}"
    textColor: "{colors.ink-light}"
---

# Design System: BRIGHTMESS

## Overview

**Creative North Star: "Source Deck"**

Three kinds of action share one small Mac popover. The forest band changes what the TV shows; the sage shelf brings a particular Mac window to the opening display; the quieter ground adjusts each display’s output. The deck should make the consequence of the next click visible before the click.

**Key Characteristics:**

- Three equal source keys, with a route printed on each.
- One tile per window, even when several belong to the same app.
- Display outlines follow desktop proportions and order.

Native fixture captures: [Samsung destination · light](docs/source-deck.png) and [TV destination · dark](docs/source-deck-dark.png). These are rendered examples, not physical test records. The [Light Gate archive](docs/archive/light-gate/README.md) preserves the previous direction.

## Colors

The Desk Plan palette gives the three jobs different grounds. Forest and cream stay fixed across appearances; pear labels the three source keys. Out of Register uses emerald glass, a lime stripe and an amber pixel in the header and menu bar. On the lower deck, the adaptive shelf, ground, ink, muted text, button face, outline and accent switch with macOS appearance. Use the adaptive accent for native sliders, toggles and actions.

**The Command Rule.** A source key sends a request. Its colour does not identify the picture currently on the TV.

## Typography

Use the Mac system sans throughout. “TV source” gets the largest, tightest line; each source name is the next size down, with its route beneath. The section titles lead the shelf and levels without competing with the source keys. The maker imprint is small, bold and tracked. Put an app’s name above its window title; keep both on one line and expose the full action through the help and accessibility label.

## Layout

Dimensions below are logical Mac points; machine-readable sizes use the same numbers in CSS pixels for previews. The 450-point popover keeps its 36-point status strip and footer fixed. The body scrolls; height is available screen height less 52 points, clamped to 320–595. Use a common 16-point inset across bands. Place sources first, the window shelf second and levels third. Window tiles scroll horizontally; display controls occupy a two-column grid ordered by desktop x-position, not by vendor or destination.

## Elevation & Depth

Depth comes from coloured bands, a fine rule around each window tile and dividers at the section boundaries. No custom shadow or glass treatment is needed on the deck. Native controls keep their own focus and pressed treatments.

## Shapes

Use compact, gently rounded keys and smaller outlined window tiles. The large symbol in each source key tilts into its upper-right corner, clipped to the key; it never replaces the written name. Display glyphs are outlined bounds fitted to a 24 × 22-point box inside a 27 × 25-point target area; unknown dimensions use the system display symbol.

## Components

- **Status strip and menu-bar mark.** Wide TV on the left, upright screen on the right, matching lime stripes and one amber pixel beyond the bezel. Opening Source Deck lifts the stripes together and snaps the pixel into registration. Reduce Motion goes straight to the aligned pose; the mark is static at rest. The 23 × 17 original-colour mark keeps solar/attention cues above the TV and names its state for accessibility.
- **App icon.** The same two screens sit on a forest glass tile in Finder and System Settings. This is a brand mark, not a live readout or current desktop map; actual geometry belongs in the display controls. See the [layered icon source](Assets/Brand/BRIGHTMESS.icon) and [native-size proof](docs/brand-icons.png).
- **Source keys.** Show PS5, Mac mini and Smart TV side by side. Name the route beneath the action: HDMI 1, HDMI 3, Home or Input chooser. A chooser action gains an ellipsis. Keep pairing, setup and command feedback in the source band; disable keys until the remote is ready.
- **Window shelf.** “To” names the opening display; “From” names the other connected displays. Each tile pairs a 24-point app icon (or fallback) with one eligible window. Keep “Move focused window” separate: it toggles the captured window to the other display, not necessarily to the shelf destination. Show a reason when the shelf is empty, and offer Accessibility access when required.
- **Display levels.** Each device owns its slider, step buttons, Follow Air switch, details and connection control. Distinguish last set, hardware readback, software dimming, unavailable and disconnected. Protect the last active display with a disabled “Last screen” action. Details, shortcuts and diagnostics expand inline.

## Do's and Don'ts

- Do show the destination by name and include the app and window title on a shelf tile.
- Do keep availability, output origin and permission states legible in words.
- Do show active shortcut bindings only; Smart TV remains click-only.
- Don't treat switching HDMI, moving a Mac window and disconnecting a display as interchangeable.
- Don't substitute a percentage or a colourful thumbnail for the origin of a display reading.
- Don't infer live TV or window-move acceptance from a rendered fixture.
