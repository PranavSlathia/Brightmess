# BRIGHTMESS release history

## 0.10.0 · Source Deck on the Mini (build 12)

- Green light/dark layout: three direct TV source actions, a destination-aware
  window shelf, and independent display controls based on actual desktop geometry.
- Open on either screen to see eligible windows from the other immediately.
  App icons and individual window titles are local. Switching inputs and moving
  windows remain independent. No Screen Recording or Air update.
- Existing shortcuts, customized icons, TV mapping, pairing, calibration and
  Follow settings retain their identifiers. The Mini installer backs up the
  previous app, helper and receiver LaunchAgent before replacing them.

## 0.9.1 · Shortcuts & icons on the Mini (build 11)

- Light desk has an editor for the move-window, PS5 and Mac mini global
  shortcuts and all four action icons. Smart TV Home remains click-only.
  The suggested keys are ⌃⌥⌘M, ⌃⌥⌘1 and ⌃⌥⌘2. Existing move bindings
  migrate, and an unavailable key does not displace a working binding.
- Window movement uses the focused window's display in either direction.
  TV shortcuts use the same paired input mappings as the buttons, without
  opening the menu or replaying an offline request. No Air update is needed.

## 0.9.0 · Light desk on the Mini (build 10) · 2 November 2026

- **TV inputs:** pair a TV from the Mini and request Home or a mapped HDMI
  input. On the iFFALCON TCL G07, Home and return to the Mac desktop on HDMI 3
  were physically verified over Wi-Fi. HDMI 1's ID was discovered; switching
  to the PS5 was not tested. Port-ID discovery was a separate research step,
  not a feature shipped in build 10.
- **Windows:** bring a selected Mac window to the display where Light desk
  opened, or assign a shortcut to move the focused window between two
  displays. These actions do not select a TV input. Window moves and Magic
  Keyboard brightness keys require Accessibility; neither requires Screen
  Recording.
- **Upgrade:** the Mini app is now named BRIGHTMESS. Its installer backs up
  the previous app and LaunchAgent and preserves the receiver arguments.
  A working 0.8 Air helper needs no update.

[Setup, exact G07 input mapping, failed alternatives, and test results](research/LIGHT-DESK-0.9.md).

## 0.8.0 · Live brightness sync and per-screen learning

The Air publishes brightness changes while awake, with a heartbeat for quiet
periods. Each automatic display learns a separate curve from the user's
adjustments. A missing live Air reading eventually switches brightness to
solar fallback; it does not synthesize room colour. Mini build 9 introduced
the illustrated Light desk. [Verification and measurement limits](research/IMPLEMENTATION-0.8.0.md).

## 0.7.0 · Ambient colour and per-display control

The scheduled helper added ambient-light and colour readings, and the Mini
applied white balance independently per display. Those are True-Tone-like
corrections, not Apple's proprietary True Tone transform.
[Integration evidence](research/IMPLEMENTATION-0.7.0.md) ·
[original open-source assessment](research/TRUE-TONE-ASSESSMENT-2026-11-01.md).
