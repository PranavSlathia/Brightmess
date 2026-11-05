# BRIGHTMESS release history

## 0.12.3 · Wait for transitioning window geometry (Mini build 26)

- Fix full-screen retrieval stopping after a window restored its smaller size:
  WindowServer briefly withdraws that same window's geometry during the exit
  animation. Treat this as temporary unavailability, not proof of closure.
- Retry only geometry reads within the existing full-screen/move deadlines,
  with a bounded pre-move read retry. Preserve PID, native ID, destination,
  cancellation and permanent-closure checks; never replay movement commands.
- Reject animation-scaled rectangles that disagree with the logical AX size;
  require a short stable period before movement and before reporting completion.
  The build-25 trial was rolled back when a rapid reverse move exposed this edge.
- Briefly refresh an opening inventory whose window geometry is still transitioning,
  instead of immediately presenting a misleading empty list. No idle polling.
- Validate full-screen Samsung-to-TV retrieval and immediate normal moves in both
  directions using the owned native AppKit fixture. The user subsequently confirmed
  Terminal moves correctly; installed TV, Air sync and keyboard status stayed healthy.
- Keep the stable signing identity and existing TV, brightness and shortcut settings.
- [Native checks, installed verification, and Terminal confirmation](research/WINDOW-TRANSITIONS-0.12.3.md).

## 0.12.2 · Correct window screen assignment (Mini build 24)

- Resolve window position from WindowServer metadata by exact window ID and owner.
  This fixes Aside appearing under Samsung while physically displayed on the TV
  when its Accessibility origin remains `(0, 0)`.
- Use the corrected position for both picker directions, the Source Deck shelf,
  focused-window moves, full-screen checks and move verification. Revalidate a
  captured native window ID; never substitute a same-sized sibling window.
- Query metadata once per inventory and refresh only during explicit movement.
  No screenshots, Screen Recording permission, polling service or TV changes.
- Preserve stable signing, TV pairing, input mappings and existing shortcuts.
  [Native and physical verification](research/WINDOW-GEOMETRY-0.12.2.md).

## 0.12.1 · TV identity continuity (Mini build 23)

- Find the existing TV certificate by the tagged key's public-key hash. macOS
  canonicalized its display label, causing the old lookup to miss and regenerate
  certificates. Keep the existing key, pairing, pins and HDMI mappings.
- Never create a certificate on background reconnect. Explicit pairing may
  create one when genuinely missing; authorization failures are not false misses.
- Bound identity loading to 30 seconds, preserve cancellation, and prevent
  discovery callbacks from restarting an in-progress identity request.
- Prepare TLS signing authorization on the utility loader before the handshake,
  avoiding the observed shared-network-queue stall while Keychain waits.
- Require a configured, verified stable signing certificate for installation,
  check online revocation, and enforce continuity with an already-signed app.
  No silent ad-hoc fallback, private-key export or automatic ACL changes.
- Build 22 was rolled back during live verification when TLS authorization
  blocked networking; build 23 includes the pre-handshake authorization safeguard.
  [Identity continuity verification](research/TV-IDENTITY-0.12.1.md).

## 0.12.0 · Bring Here window picker (Mini build 21)

- Add the compact native picker with a configurable **Control + Option + Space**
  shortcut. Initial letters select apps, numbers disambiguate windows, arrows
  select/change destination, `/` searches and Escape cancels. Existing shortcuts
  and all main-menu controls stay intact; a cleared picker binding stays cleared.
- Freeze displayed key assignments, bind operations to exact windows and refuse
  closed, relocated, permission-denied or disconnected targets. No TV command
  is involved in opening the picker or retrieving a window.
- Add guarded full-screen exit, bounded settling and verified movement where
  the app exposes the required Accessibility controls. Partial-display or
  unsupported full-screen windows require manual exit; no blind key synthesis,
  private Spaces manipulation or automatic Split View teardown.
- Work only on demand, cancel stale inventory and in-flight continuations,
  preserve portrait fitting, and keep titles out of network diagnostics.
- Installation and real-app acceptance are recorded separately in the feature
  [verification note](research/BRING-HERE-0.12.0.md); fixture tests alone do not
  qualify full-screen behavior.

## 0.11.3 · Readable TV setup controls (Mini build 20)

- Replace inherited automatic button colours in TV setup with cream labels,
  quiet filled plates and visible borders. Disabled actions stay readable
  but visually distinct; pressed and focus styling use the existing palette.
- Scope the native dark control palette to the fixed forest TV band so HDMI
  selector values, disclosure arrows and text fields remain legible in both
  macOS appearances. The rest of Source Deck keeps its adaptive appearance.
- Preserve all controls, shortcuts, TV pairing, HDMI mappings and display
  settings. No Air helper update or TV source command is part of this repair.

## 0.11.2 · Paired-TV recovery and visible code setup (Mini build 19)

- Reconnect using the last authenticated TV address when Bonjour is missing.
  A bounded read-only TCL LAN probe can locate a changed address; every
  candidate must still match the existing TLS key pin. Discovery is not trust.
- Keep a healthy session when its Bonjour advertisement disappears. Back off
  unavailable connections up to 60 seconds; cancel discovery on sleep or
  when the control session is no longer needed.
- Restore **Pair again with TV code** in setup even while disconnected.
  Secure six-character entry, Verify and Cancel remain inline. An optional
  local TV-address field handles networks that block discovery. Preserve
  the saved pairing until the physical TV code proof succeeds.
- Distinguish **Pairing saved** from **TV connected**. Keep input mapping
  editable while offline. No re-pairing, input switch or command replay is
  triggered by recovery itself. No Air update or Samsung source test.
- Load the existing Keychain identity off the main thread and coalesce
  concurrent requests, so a macOS permission prompt cannot freeze the menu
  or prevent the brightness receiver from starting.
  [Recovery evidence](research/TV-RECOVERY-0.11.2.md).

## 0.11.1 · Editable TV HDMI assignments (Mini build 17)

- Store the physical HDMI port with each TV action instead of hardcoding
  PS5 to HDMI 1 and Mac mini to HDMI 3. Captions, button routes and existing
  shortcuts share that assignment, including standard-key fallbacks.
- Add port pickers in **Set up → Configure TV inputs…**. Saved per-TV input
  IDs fill the advanced field for a selected port; no device-ID guessing or
  automatic switching occurs. Reject duplicate and mismatched routes.
- Preserve existing pairing, icons, keys and legacy assignments. Saving a
  mapping sends no source command. Fix light-mode input-field contrast.
- This desk is configured for Mac mini HDMI 1 and PS5 HDMI 2 from a fresh
  TCL port-list query and the user's new cable layout. Physical picture
  verification for those new assignments is separate.
  [Investigation and verification](research/TCL-REMAP-0.11.1.md).

## 0.11.0 · Samsung readback and gated sources (Mini build 16)

- Correct GET-VCP framing: include the host source byte in the request
  checksum. The LU28R55 now returns valid hardware brightness rather than
  being described as unable to provide readback.
- Separate measured brightness, its age, mapped target and last hardware
  command. Verify settled writes once; refresh while the menu is visible,
  with failed-read backoff and no closed-menu idle polling.
- Add Samsung DisplayPort/HDMI 1/HDMI 2 names, optional shortcuts, input
  readback and an explicit round-trip setup. HDMI actions remain disabled
  until the user confirms both physical pictures and return readback passes.
- Guard source writes with the selected monitor's current identity and a
  checksum-valid direct-channel EDID. Do not replay offline source changes.
- No Air update, standby, contrast, RGB or PIP/PBP control is added.
  [Evidence and outstanding physical checks](research/SAMSUNG-CONTROL-0.11.0.md).

## 0.10.3 · Display recovery (Mini build 15)

- Resolve reconnects using current EDID/IORegistry port evidence, not the
  number of cached vendor/model/serial matches. Ignore stale WindowServer
  slots; keep refusing genuinely ambiguous monitors before any disconnect.
- Re-resolve identity if enabling allocates a new display ID; do not submit
  an enable transaction for a monitor that a cable replug already restored.
- Clear a stale reconnect error when the screen returns. Restore its mapped
  automatic level or saved manual level once on the rebuilt output route,
  without learning a match, changing Follow, or rewriting a settled target.
- Retain known screen cards after physical cable loss and keep recovery data
  on failed commits. A macOS rejection now gives cable/input/power recovery
  guidance. Software cannot promise to repair a failed physical handshake.
- No Air update, TV input changes, new permission types or network service.
  Replacing the locally signed app can require Accessibility reapproval.

## 0.10.2 · Out of Register (Mini build 14)

- Matching native app and menu-bar icons: a wide TV and upright monitor share
  a lime stripe, with one amber pixel outside the bezel.
- The menu-opening cue plays once, respects Reduce Motion, and never switches
  TV inputs or modifies brightness. The Air helper is unchanged.

## 0.10.1 · Glass Firefly (staged, superseded)

- New layered macOS app icon and legacy icon fallback for Finder and System Settings.
- Full-colour firefly in the menu bar and Source Deck header. Solar and attention
  retain distinct shape cues and accessible labels. No Air update or new permissions.

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
