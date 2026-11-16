---
name: BRIGHTMESS
description: A native Mac source deck for TV inputs, individual windows and display levels.
colors:
  forest: "#153D2F"
  picker-cream: "#F4F9E9"
  pear: "#DDEBBA"
  leaf: "#C5ED70"
  ground-light: "#FFE0A3"
  ground-dark: "#923912"
  rule-light: "rgb(120 49 16 / 32%)"
  rule-dark: "rgb(255 228 185 / 32%)"
  shelf: "rgb(255 180 62 / 8%)"
  button-light: "rgb(255 227 168 / 13%)"
  button-dark: "rgb(212 142 74 / 13%)"
  accent-light: "#7C280B"
  accent-dark: "#FFE1A8"
  amber: "#FFB65C"
  warm-ink-light: "#2B160A"
  warm-ink-dark: "#FFF3D9"
  muted-light: "#4E2817"
  muted-dark: "#FFEBD2"
  key-label-light: "#2B160A"
  key-label-dark: "#FFFFFF"
  glass-tint-light: "#FFB634"
  glass-tint-dark: "#A1430B"
  dawn-light: "#FFDE66"
  noon-light: "#FFAC57"
  dusk-light: "#FF7E84"
  dawn-dark: "#8A3304"
  noon-dark: "#86260F"
  dusk-dark: "#74152F"
typography:
  headline:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "27px"
    fontWeight: 600
    letterSpacing: "-0.5px"
  source:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
  section:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  device:
    fontFamily: "system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 700
  imprint:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    letterSpacing: "0.4px"
  route:
    fontFamily: "system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
rounded:
  source: "14px"
  home: "10px"
  utility: "7px"
  window: "8px"
  device: "11px"
spacing:
  tile: "5px"
  key: "11px"
  levels: "12px"
  gutter: "16px"
components:
  status-strip:
    height: "40px"
    typography: "{typography.imprint}"
  source-key:
    rounded: "{rounded.source}"
    padding: "0 11px"
    height: "62px"
    typography: "{typography.source}"
  source-home:
    rounded: "{rounded.home}"
    height: "29px"
    padding: "0 10px"
  utility-button:
    rounded: "{rounded.utility}"
    padding: "5px 9px"
  window-tile:
    width: "135px"
    height: "37px"
    rounded: "{rounded.window}"
  window-tile-dark:
    width: "135px"
    height: "37px"
    rounded: "{rounded.window}"
  display-glyph:
    width: "27px"
    height: "25px"
  footer:
    padding: "11px 16px"
---

# Design System: BRIGHTMESS

## Overview

**Creative North Star: "Source Deck · Solar Glass"**

Three kinds of action share one small Mac popover: what plays, what moves and what dims. The whole panel mixes shades of sun through native glass: gold, orange and coral in light appearance; burnt orange and red sunset in dark appearance. Rounded system headings and glossy tinted keys preserve the existing hierarchy. The user-pinned Solar Glass direction rejects neutral white or black glass with tiny amber accents, as well as opaque section bands and postcard slab lettering. It applies to Source Deck, not the separate green Bring Here picker.

**Key Characteristics:**

- Two equal glass source keys and a quieter full-width Home row, with routes printed on each.
- One tile per window, even when several belong to the same app.
- Display outlines follow desktop proportions and order.

Current native Solar Glass fixtures: [light](docs/source-deck.png), [dark](docs/source-deck-dark.png) and [shortcuts](docs/shortcuts-and-icons.png). These are native captures over a synthetic fixture backdrop, not installed-hardware evidence. They establish rendered appearance, not physical TV, installed-app or motion acceptance. The [Light Gate archive](docs/archive/light-gate/README.md) preserves an earlier direction.

## Colors

The continuous dawn-to-noon-to-dusk gradient colours the entire panel from top-leading to bottom-trailing: 80% over native material in light appearance, 86% in dark appearance. Reduce Transparency keeps the same gradient at full opacity. Source glass uses the adaptive glass tint at 35% for PS5 and Mac mini and 22% for Home. Warm adaptive ink and muted text preserve legibility over the chromatic surface; enabled source labels use deep brown in light appearance and white in dark appearance. Small faces and rules use adaptive warm tones. Native sliders, toggles and actions use the adaptive accent. Forest, picker-cream, pear and leaf remain legacy/picker tokens, not Source Deck controls. The unchanged brand sun uses gold (`#FFD255`), amber (`#FF9945`) and forest ink (`#142E26`): logo colours, not state colours.

**The Command Rule.** A source key sends a request. Its colour does not identify the picture currently on the TV.

## Typography

Use semibold rounded system type for the imprint, TV heading, source names and section headings. Keep system sans for routes, status, device names, utility controls and window metadata. “TV source” is 27 points; source names 18; sections 16; imprint 14. Home uses a 13-point semibold system label. Put an app’s name above its window title; keep both on one line and expose the full action through help and accessibility labels. The separate Bring Here picker retains system typography.

## Layout

Dimensions below are logical Mac points; machine-readable sizes use the same numbers in CSS pixels for previews. The 450-point popover keeps its 40-point status strip and footer fixed. The body scrolls; height is available screen height less 52 points, clamped to 320–595. Use a common 16-point inset across bands. Two equal 62-point TV keys sit above the full-width 29-point Home row; the window shelf follows, then levels. Window tiles scroll horizontally; display controls occupy a two-column grid ordered by desktop x-position, not by vendor or destination.

## Elevation & Depth

One root NSVisualEffectView supplies active popover material with behind-window blending in production, under the full-panel solar gradient. Within-window blending exists only for fixture backdrops. On macOS 26 and later, one GlassEffectContainer (8-point spacing) groups the source keys; enabled keys use regular interactive native glass. Native material owns gloss and interaction, with no custom moving light sweep or enamel shadow. Press adds a 12% amber wash and a mild 0.985 scale over 120 ms ease-out. Reduce Motion removes scale and animation. Reduce Transparency uses the full-opacity solar gradient and non-glass source keys with opaque adaptive ground; older macOS uses low-opacity faces and borders. Disabled keys use warm muted text and a dashed border, while increased contrast strengthens fallback borders to warm ink. Native fields, sliders and switches retain native interaction treatments.

## Shapes

Use 14-point source-key corners, 10-point Home corners, 7-point utility corners, 8-point window tiles and 11-point display cards. Compact upright source icons accompany written names; keyboard badges occupy the upper row. Display glyphs are outlined bounds fitted to a 24 × 22-point box inside a 27 × 25-point target area; unknown dimensions use the system display symbol.

## Components

- **Status strip and menu-bar mark.** A winking gold sun with uneven rays, a lopsided grin and one amber ray that has broken ranks. Opening Source Deck gives that ray one short flick; the panel and other rays stay still. Reduce Motion uses the static mark. The 23 × 17-point mark keeps solar fallback and attention badges separate from the sun and names their states for accessibility.
- **App icon.** The same sun sits on an appearance-adaptive tile in Finder and System Settings. It is the brand, not a brightness meter, warning or desktop map. See the [layered icon source](Assets/Brand/BRIGHTMESS.icon) and [native-size proof](docs/brand-icons-1x.png).
- **Source keys.** Show equal PS5 and Mac mini keys above the full-width Smart TV Home row. Beneath PS5 and Mac mini, show each action’s saved HDMI port, or “Input chooser” if configured. A chooser action gains an ellipsis. Keep pairing, setup and command feedback in the source band; disable keys until the remote is ready.
- **TV pairing.** “Pairing saved” means the Mac remembers the TV; show “TV connected” only when the remote is ready. Keep “Pair again with TV code” visible in setup even while the TV is offline. Show the secure six-character field, Verify and Cancel inline, and keep the saved pairing until the new code is verified.
- **TV setup controls.** Over the shared solar material, use warm ink on a low-opacity adaptive warm button face with a 1-point rule border and 9 × 5-point horizontal/vertical padding. Disabled controls retain readable muted text and gain a dashed (3, 2) border. Enabled focus uses a 2-point ink outline; press adds a 10% ink wash. Native fields, pickers and disclosures follow macOS appearance; do not force dark mode on the band.
- **Window shelf.** The destination chip names the opening display; “From” names the other connected displays. Each tile pairs a 24-point app icon (or fallback) with one eligible window. “Window picker” opens the dedicated Bring Here panel and shows its shortcut only when registered. Keep “Move focused window” separate: it toggles the captured window to the other display, not necessarily to the shelf destination. Show a reason when the shelf is empty, and offer Accessibility access when required.
- **Display levels.** Each device owns its slider, step buttons, Follow Air switch, details and connection control. Distinguish last set, hardware readback, software dimming, unavailable and disconnected. Protect the last active display with a disabled “Last screen” action. Details, shortcuts and diagnostics expand inline.

### Bring Here picker

A compact, destination-first AppKit panel using the existing forest header, cream heading, adaptive green ground and system typography. It is 376 points wide with a 304-point base height, grows to six visible 48-point rows before scrolling, and adds space for an inline notice. The rounded panel uses the native window shadow and sits near the upper-middle of the destination's usable bounds.

Each row has a native app icon or window-symbol fallback, an app name above a separate window-title or state line, and a bordered letter or number keycap. Truncated details remain available through help and accessibility labels. Selection has both a fill and outline; rows expose accessibility-selected state, and selection changes request an announcement naming the destination and window. Actual VoiceOver delivery still requires native acceptance.

The opening destination is captured from the pointer display. Left/Right changes it in app and numbered lists; it stays fixed when the pointer moves. Release the trigger modifiers before selecting. A displayed initial retrieves a sole match or opens a numbered group; Up/Down or Tab/Shift-Tab and Return provide an alternative. The first nine group entries have number keys; further entries remain reachable through navigation and scrolling. `/` opens an explicit native search field, where typing filters app and window names and Left/Right edits text. Escape backs out of search or a group, then closes the picker. Recovery states pass native traversal and activation keys through to the focused Open Accessibility settings or Refresh choices button, with Return available to activate it.

Loading, no eligible windows, no search matches, permission loss, missing or changed displays, unsupported windows and failed moves have explicit text states. A supported full-screen entry says it exits to move; the adapter capability-checks the exact window, waits for observed exit and verifies movement before focusing it. This is not universal full-screen or Split View support. Progress stays inside the panel; cancellation stops further steps but cannot undo an already-sent full-screen exit. TV inputs and brightness controls are separate from retrieval.

Control–Option–Space is the configurable default attempted once by the shortcut setup, without replacing existing bindings or restoring a deliberately cleared binding. The 18 light/dark production-native picker fixtures establish rendered/source evidence only. [Native and installed verification](research/BRING-HERE-0.12.0.md) and [transition acceptance](research/WINDOW-TRANSITIONS-0.12.3.md) are recorded separately. No new shipping raster assets were introduced for this panel.

### Workflow additions (0.14)

Bring Here keeps its compact green visual language. A small pin symbol marks
pinned app groups; Manage pinned apps sits above the keyboard legend and also
responds to Command–Comma. The separate native pin editor supports reorder,
remove and add without reshuffling a picker already on screen. Pins and recent
retrievals change ordering, not the initial/number/search interaction contract.

Check my setup is a separate, resizable reading window reached from Desk
details. Use literal section headings, explicit status symbols, warm legible
ink and the existing utility button treatment on the native window surface.
The top suggested recovery is a user action, never an automatic repair.
The report body scrolls while Refresh and Export remain available. Export
opens a frozen, selectable JSON preview before the native save dialog.
See [fixture provenance and acceptance](docs/WORKFLOWS-0.14.md).

### Arrange here

The action row sits with window controls, separate from TV and brightness
actions. It opens transparent, full-screen zone outlines on the pointer's
display and a 540-point floating native control bar near its lower edge.
Opaque forest label chips show app names and window titles. Smart/Equal changes
the preview; window checkboxes and All/None choose participation. Apply and
Undo are explicit; normal preview interaction must never move windows.

Use the existing adaptive ground/ink and native control states. Reduce
Transparency removes zone fill, retaining labels and outlines. No continuous
animation or polling is needed. Enter applies, Command-Z undoes and Escape
closes/stops. The optional shortcut and action icon use the existing editor.
For the build-33 interaction, the control bar is 200 points high, or 350 with
the window checklist expanded. All eligible windows start selected. Apply gets
initial focus, but a fresh Enter/keypad Enter works from other controls too.
The opening chord must be released first; key repeats and loading-state Enter
never queue an Apply. Show the compact Enter / S Smart / E Equal / W Windows /
Esc legend. Preserve Tab, Space and text-entry behavior.
Fully successful Apply closes the bar and restores the previously active app
only if BRIGHTMESS still owns focus. Errors, partial results and Undo results
stay visible. Closing/reopening or a no-op Apply must preserve the last useful
Undo; a new meaningful arrangement replaces it. No cursor warp.
Fixture previews and native acceptance are tracked in [Arrange here](docs/ARRANGE-HERE.md).

## Do's and Don'ts

- Do show the destination by name and include the app and window title on a shelf tile.
- Do keep availability, output origin and permission states legible in words.
- Do show active shortcut bindings only; Smart TV remains click-only.
- Don't treat switching HDMI, moving a Mac window and disconnecting a display as interchangeable.
- Don't substitute a percentage or a colourful thumbnail for the origin of a display reading.
- Don't infer live TV or window-move acceptance from a rendered fixture.
