# Samsung readback and gated source controls · 0.11.0 / build 16

## Evidence boundary

Build 16 is installed and passes the checks below. Physical source
qualification is a separate gate, not implied by installation, a DDC write
acknowledgement or fixture screenshot. No Samsung source change has been
sent during implementation. HDMI 1 and HDMI 2 remain unqualified.

## Root cause and reference

The production GET-VCP brightness request used `82 01 10 FD`, omitting the
host source byte `51` from its checksum. On this Mini-to-Samsung DisplayPort
connection that returned repeated null replies (`6E 80 BE`), not a valid VCP
value. Correct request `82 01 10 AC` produced the checksum-valid reply
`6E 88 02 00 10 00 00 64 00 34 F4`: brightness 52 of 100 at that measurement.
A subsequent read-only production-driver probe measured 94 of 100 while the
Air's mapping and installed build 15's last command were also 94. These are
time-specific reads, not fixed defaults or a physical OSD comparison.

The MIT [m1ddc source](https://github.com/waydabber/m1ddc) was cloned to ignored
`research/repos/m1ddc` at revision
`7339ceebb03f691b1eaeb8471dca301d215d19c8`; `sources/i2c.m` includes the source
address in its GET checksum. BRIGHTMESS adapts that framing, not a service or
binary dependency. Existing third-party notice credit is retained. Strict
reply validation remains in place. The SET framing was already correct.

The direct IOAV-service EDID was checksum-valid and matched the Samsung's
vendor, model and serial, rather than the TCL. Research GETs also measured
input 15 (DisplayPort), contrast 88/100 and the other values in the
[read-only assessment](samsung-u28r55-assessment-2026-11-03.json). That earlier
assessment is a historical pre-fix snapshot, not current installed status.

## Why source commands are gated

This unit's capability string advertises `60(01 03)` although its actual input
read is 15. The reported VCP maximum 3 is not a cap on legal source codes.
Codes 17 and 18 are conventional candidates only; the exact-family
[Monitorian report](https://github.com/emoacht/Monitorian/issues/304) also
records intermittent DDC responses. No mapping from another Samsung is
accepted as physical proof for this desk.

Each source write re-resolves the stable display identity and validates a
direct-channel EDID on the same retained transport used for VCP 0x60. It fails
closed rather than choosing a stale numeric display ID or the TV's channel.
No brightness, power, reset, disconnect or TV-source command is part of this
operation. No command is queued for a later reconnect.

DisplayPort code observation enables only the known return action. HDMI
requires an explicit test with an awake source, another usable Mac screen
and JOG recovery available. The test sends the candidate once, waits about
three seconds plus transport time, and sends the observed DP code once.
Conflicting target readback or a failed DP readback cannot qualify the port.
After successful return readback, the user must confirm both physical images
within five minutes. A failed outbound write has an unknown physical outcome
and directs the user to JOG recovery. Cancellation or interruption never
replays a delayed source request. Each HDMI route is qualified independently.

The versioned profile persists a route name, code, stable target and physical
port evidence. Renaming preserves proof; remapping clears it. Changing the DP
return code clears all source proofs. Global source shortcuts are optional
and initially unassigned, with the existing conflict checks and custom icons.

## Readback behavior

Actual brightness, read time and last write time are independent fields. A
reading must be no older than 15 seconds and newer than the latest hardware
command to be live. Failures retain an explicitly older reading or last-set
command, not invented measurement. Settled writes get one verification read;
visible-menu reads have a five-second interval or 30-second failure backoff.
The visible age timer stops with the menu. No closed-menu steady-target read
loop or read-after-every-fade-step loop was added. Software shades are not
hardware-polled. Readback does not teach calibration or disable Follow.

## Automated verification

- The production C request builder first failed the new checksum check with
  `820110FD`, then passed with `820110AC`. Request bounds and actual Samsung
  reply decoding reject null, corrupt, wrong-code and truncated replies.
- Fake-driver readback tests cover cached 100 vs measured 52, settled manual
  verification, stale/error freshness, failed-read backoff, ignored writes,
  unchanged Follow/calibration and zero closed-menu steady reads/writes.
- Fake Samsung tests cover the physical-confirmation gate, independent
  routes, offline no-replay, ignored commands, uncertain outbound writes,
  failed return and cancellation before a delayed return.
- Full executable loopback simulation passes, including existing live Air,
  ordering, learning, fade, recovery, window shelf and shortcut checks.
- Release build and 27 executable core checks pass. Full Xcode 27.2 runs
  29 Swift Testing tests successfully; the system CLT is not changed.
- Native light/dark, details, 320-point-height, setup and error fixtures are
  under `.impeccable/review/samsung-sources/`. They use synthetic window
  titles and fake drivers, not screenshots proving hardware behavior.

## Installed verification · 3 November 2026

- Installed Mini 0.11.0 / build 16. Current and backed-up build 15 app
  signatures verify. Rollback script syntax verifies; it was not executed
  against the working desk merely to test a downgrade.
- App, CLI and receiver LaunchAgent rollback:
  `~/Library/Application Support/Brightness Relay/Backups/20261103-145501.p4hqeD`.
  A separate private settings snapshot is
  `~/Library/Application Support/Brightness Relay/Backups/Samsung-state-build15-20261103.zjkPyf`.
  Pairing token and receiver arguments compare byte-for-byte unchanged.
- Both stable display identities, Follow settings, calibration counts
  (Samsung two, TV one immediately before install), old shortcuts and icons
  survived replacement. The Samsung's existing learned mapping was 88 while
  the TV's was 94; the app does not erase their independent calibration.
- The installed receiver accepted fresh signed live updates from the same
  Air session. The paired TCL remote session is ready; no TV input was sent.
- Opening the menu requested only reads. The installed Samsung driver read
  brightness 88/100 and input 15; source setup recorded the DP code but kept
  both HDMI routes unqualified. This is hardware readback, not a physical OSD
  comparison or source-switch test.
- Across an observed 20.08-second settled closed-menu interval, hardware
  read attempts, hardware writes and software writes all had zero deltas.
  This focused idle check is not a ten-minute CPU performance measurement.
- The new ad-hoc executable needs Accessibility reapproval. Existing TV
  shortcuts are registered, but window moves and brightness keys are not
  considered reverified until the user re-adds the installed app. No TCC
  database or system permissions were reset automatically.
- Impeccable's fresh finish review disposition is **ship the gated UI**,
  scoped to UI/code/fixtures after resolving two safety labels. The separate
  documenter checked all eight captures and preserved DESIGN.md and its
  sidecar. Existing unused token drift was reported, not repaired.

## Physical acceptance still required

1. Compare a current app hardware read with the Samsung's own brightness OSD.
2. Keep the Mini's DP cable connected, the TCL on its Mac input, and open
   BRIGHTMESS on the TCL. Connect an awake device to Samsung HDMI 1.
3. Start the explicit round-trip test. Observe the HDMI picture and automatic
   Mac DP return without using JOG. If return fails, restore DP with JOG;
   the route stays disabled. Confirm success only after seeing both pictures.
4. Repeat independently on HDMI 2. Test return with the app/shortcut while
   HDMI is showing; do not infer inactive-port command support from DP reads.
5. Verify live Air following and the existing Magic Keyboard/window/TV
   controls after installation and any Accessibility reapproval.

Contrast, RGB, physical standby and PIP/PBP are deferred. This release does
not advertise Samsung source support as universally qualified.
