---
name: BRIGHTMESS
description: A macOS instrument for moving light, windows and TV inputs between two screens.
colors:
  ink: "#13262B"
  spruce: "#1F4A4D"
  mint: "#B0E0BF"
  gold: "#FCC761"
  coral: "#F78C6B"
  cream: "#FAF2D6"
  paper: "#F7F5EB"
  surface-light: "#FEFCF5"
  surface-dark: "#1D3437"
typography:
  display:
    fontFamily: "ui-serif, serif"
    fontSize: "35px"
    fontWeight: 700
    letterSpacing: "-1.25px"
  device:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "19px"
    fontWeight: 700
  state:
    fontFamily: "system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  small-action:
    fontFamily: "system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
  imprint:
    fontFamily: "system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 700
    letterSpacing: "1.5px"
rounded:
  picture: "7px"
  utility: "8px"
  device: "11px"
spacing:
  close: "5px"
  control: "8px"
  strip: "12px"
  header-y: "14px"
  header-x: "19px"
components:
  status-mark:
    width: "23px"
    height: "17px"
  source-header:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.cream}"
    typography: "{typography.display}"
    padding: "14px 19px"
  sync-button:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.cream}"
    typography: "{typography.small-action}"
    padding: "5px 8px"
  device-strip:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.device}"
  device-strip-dark:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.device}"
  device-picture:
    width: "114px"
    height: "88px"
    rounded: "{rounded.picture}"
  brightness-slider:
    backgroundColor: "{colors.spruce}"
  desk-footer:
    typography: "{typography.state}"
    padding: "11px 16px"
---

# Design System: BRIGHTMESS

## Overview

**Creative North Star: "The Light Gate"**

An enlarger in a darkroom holds a sheet still while the light above it changes. Treat the desk the same way: the upright Samsung and the wide TV are the fixed frame; the picture inside each frame can brighten, dim or disappear. The menu-bar mark is that instrument in miniature. It must still read as two different screens at a glance.

Pranav opens Light desk on the portrait monitor, sometimes in daylight, sometimes with a game lighting the room. Match the Mac's light or dark appearance. The character comes from the printed sun, cut silhouettes and registration marks, not from making controls unfamiliar. The next design should feel raw in its marks, precise in its response, and ambitious in how the icon opens into the panel.

**Key Characteristics:**

- Two recognizable silhouettes before a single percentage.
- One expressive surface around quiet, native controls.
- Changes in light belong to the screen that changed.

**Scope:** The tokens above describe Mini build 11. Sizes are macOS logical points; the preview snippets use the same numbers in CSS pixels. The glass and motion proposals below are design targets, not installed features. [Product constraints](PRODUCT.md) and the [current popover](docs/light-desk.png) are the baseline.

## Colors

Keep the controls restrained; give the illustrations the full palette. In light appearance, Paper holds the panel and the lighter device surface separates each screen. In dark appearance, Ink holds the panel and the lifted dark surface separates the screens. Use system label colors on both. The header keeps Cream on Ink in either appearance.

### Primary

- **Spruce control tint** (#1F4A4D): slider and switch tint on light surfaces.
- **Mint control tint** (#B0E0BF): tint on dark surfaces and rings around the header sun.

### Secondary

- **Printed sunlight** (#FCC761): the header sun and the warm end of the portrait sky.
- **Portrait coral** (#F78C6B): the warm sky on the portrait screen. Never use it alone to communicate an error.

### Neutral

- **Printing ink** (#13262B): the header, the chassis outlines, and the dark panel ground.
- **Header cream** (#FAF2D6): header lettering and the small sun inside a device illustration.
- **Desk paper** (#F7F5EB): the light panel ground.
- **Light device plate** (#FEFCF5): the device surface on paper.
- **Dark device plate** (#1D3437): the device surface on ink.

These colors identify places, not connection health. A disconnected screen retains its silhouette and loses its picture.

**The Exposure Rule.** Dim the picture inside the bezel. Do not dim the device name, controls, or surrounding room to convey brightness.

## Typography

**Display Font:** System serif (with serif)

**Body Font:** System sans (with sans-serif)

**Character:** Use the bold serif only for **Light desk**. Its tight tracking makes the header feel like a title printed on an instrument plate. Use the rounded system face for device names and the plain system face for actions, readings and permission prompts. Let native text styles govern body and caption sizes.

The small, tracked BRIGHTMESS imprint identifies the maker; it does not compete with the device name or action. A changed label such as **Reconnect** must fit without shrinking into fine print.

### Hierarchy

- **Display** (bold, 35 pt, tracking -1.25 pt): Light desk title.
- **Device** (rounded bold, 19 pt): the name of each screen.
- **State** (medium, 12 pt): source status and footer navigation.
- **Small action** (semibold, 11 pt): Sync now.
- **Imprint** (bold, 10 pt, tracking 1.5 pt): BRIGHTMESS at the top of the header.

## Elevation

**Shipping:** depth comes from adjacent tones, an 11-point device corner, and a one-point outline at 10% primary opacity. The small grounding shadow under a drawn monitor is part of the illustration, not a shadow around its controls.

**Next direction:** make the popover one piece of liquid glass, like a lens fitted over an inked instrument plate. Let a narrow edge catch or bend light as it opens. Keep the area beneath labels, sliders and shortcuts optically quiet. With Reduce Transparency, or where the material is unavailable, use solid Paper or Ink and a clear edge. The layout and actions must be identical.

**The One Lens Rule.** Put the glass at the boundary of the instrument. Do not put another pane around each button, slider or device.

## Components

### Menu-bar mark

Today the 23 × 17 template pairs an upright monitor on a stand with a wide TV on two feet. Rays mean linked, a low sun means solar fallback, and an exclamation means attention. Let macOS tint the template; don't add full-color detail that vanishes at this size.

### Source header and Sync now

Keep the sunlight at the far edge of the header, away from the title and Air status. Sync now is a small outlined capsule. Its label can change to Syncing or Synced without stealing focus.

### Display strip and brightness

Give each physical display one strip. Its 114 × 88 illustration opens Details; the slider, step buttons, Follow Air and Disconnect remain labeled controls. Draw an unknown reading as unknown, not as zero. Protect the last screen with **Last screen**, not a deceptively active Disconnect button.

### Windows, TV inputs and footer

Keep a move-window action separate from a TV-source action. A user-selected symbol supplements the name; it never replaces it. Reveal Shortcuts & icons and Desk details inline. The 450-point popover scrolls between a fixed header and footer instead of shrinking controls on a short display.

**Proposed motion score:**

| Event | Visible response | When it stops |
| --- | --- | --- |
| Open Light desk | One ray on the mark aligns with the header horizon. The glass edge catches that light once, then clears. Use a short ease-out, roughly 180 ms; controls are usable immediately. | At rest, the mark and lens are still. Closing can simply fade. |
| Adjust a screen | Track the gesture with the light inside that screen's illustration. The chassis and the other display remain steady. | When the applied level settles; no independent decorative loop. |
| Receive an error or fall back to solar | Change the small sky motif and show the state in words. Do not make the whole panel flash. | Hold a static, legible state until it changes. |
| Send a TV command | Give the pressed control brief local feedback. Keep **Command sent** distinct from a confirmed picture change. | End on the reported state, not a fabricated success animation. |

**The Still Desk Rule.** Animate a change, not the passage of time. With Reduce Motion, skip travel, refraction and scale; use the final static mark, label or picture immediately. No shimmer, timer or rendering loop while the menu is closed or settled.

## Do's and Don'ts

- **Do** keep the portrait stand and TV feet legible in a single-color silhouette.
- **Do** keep keyboard focus, disabled explanations and action labels visible in both appearances.
- **Do** show exact readings in Details and distinguish a hardware read from the last value set.
- **Don't** replace the desk with a dashboard of repeated percentages.
- **Don't** use glass behind text if a bright desktop can erase the label.
- **Don't** confuse dimming with disconnecting, moving a window with switching HDMI, or sending a command with seeing the picture.
- **Don't** turn a heartbeat into a pulsing icon or sample the user's desktop as artwork.
