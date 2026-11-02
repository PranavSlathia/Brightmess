# Brightness Relay 0.8.0 verification

Historical record for the live Air helper and Mini builds through 9. The
[0.9 Mini record](LIGHT-DESK-0.9.md) covers the renamed app, TV inputs and
window controls; an existing live 0.8 Air remains compatible.

1–2 November 2026, M4 Mini, portrait LU28R55 over HDMI and Beyond TV; source is PRSNL (M2 Air). A monitor percentage is not a photometric measurement.

## Implementation and scope

The Air source now combines native brightness notifications, a two-second fallback sampler with a reusable HID client, change filtering, a 60-second heartbeat, and a single latest-value send queue. It sends lifecycle and ordering metadata in the existing signed envelopes. Legacy senders remain scheduled. The Mini uses a five-minute live hold, then solar, without synthesizing colour.

Display preferences are keyed by the existing stable identities. Automatic displays learn only settled user choices against a fresh, stable Air percentage. Legacy matches are migrated into a separate v2 key. Undo and confirmed reset are local to one monitor. Automatic brightness fades coalesce; software shade and white balance remain separate. No temporary overrides, new service, desk sensor or location checks.

## Software verification

- Native release build succeeded; 21 executable core groups passed.
- Debug-only loopback runner uses the real publisher, real authenticated HTTP client/server, isolated preferences, fake sensors and fake display drivers. It passed legacy-to-live handover, event burst/final level, missed-event watchdog, per-display slider and keyboard learning, undo, four-per-second hardware limit, no writes after settling, explicit sleep and lid status, wake/Sync Now, and out-of-order rejection. A further test interrupted the real loopback TCP listener, queued changes while connections failed, and verified recovery at the newest target after the listener returned. It also rejected learning during a changing Air level and preserved explicitly manual mode.
- Core tests supply deterministic monotonic times for send coalescing, single-flight, offline exponential backoff, hold deadlines, retargeting and legacy migration. Simulations are not physical display or battery measurements.
- Swift Testing suite **not run**: this CLT lacks the `Testing` module. Shell scripts passed syntax checks; the private ZIP passed archive integrity and helper signature verification.
- Reproduce: `./scripts/swiftpm.sh build -c release`, `.build/release/brightness-self-test`, and `BR_TEST_LOG="$TMPDIR/relay-sim.log" ./scripts/swiftpm.sh run brightness-relay simulation-check`.

A key immediately following slider release previously stepped from the last hardware write instead of the just-requested manual level. The regression failed on 43 → fine-step down, then passed at 42 after using the pending manual goal. First simulated hardware adjustment in the final loopback run: 251 ms. Neither a fake driver nor local loopback establishes M2/Tailscale latency.

## Mini rollout

- Installed and verified the 0.8.0 receiver. The 0.7 rollback copy and its validated LaunchAgent are in `~/Library/Application Support/Brightness Relay/Backups/20261101-233630`. The subsequent diagnostics-only correction also has a separate backup.
- With the old Air helper, a real signed scheduled reading reported Air 62% and mapped both automatic screens to 68%. Scheduled mode was reported explicitly. No hardware adjustment was necessary at that level.
- Actual TV disconnect removed it from the active macOS display list while leaving the Samsung active. Reconnect restored the TV, its Follow setting and 68% software level. Samsung remained connected and automatic.
- The local build is ad-hoc signed; updating the Mini can require re-adding the current executable in Accessibility. Pairing token, Follow settings and the display recovery ledger were not replaced.
- Private Air bundle: `~/Downloads/Brightness-Relay-Air-0.8.0.zip`. The installer requires a verified Mini 0.8 session, creates a local backup of the old source and agent, and rolls back if the replacement fails to publish a fresh live session. The ZIP contains pairing material, not for redistribution.

## Measurement boundary

The Mini's 0.7 receiver (PID 82840) used 13.13 CPU seconds over exactly 600 wall seconds, **2.19% of one core**. This is process CPU, not energy consumption. Do not infer Air CPU, latency, physical output or network-loss recovery from this number or from simulated tests.

### Mini-only rollout checkpoint, 1 November 2026

- Ten quiet minutes on 0.8 before the pending-slider/key correction: **0.19 CPU seconds / 600 seconds = 0.032% of one core**, versus 2.19% on 0.7. The old scheduled Air helper was still supplying the Mini. Hardware/software write counters did not advance during this window. The measurement is not a live-pair or battery benchmark.
- Final corrected Mini executable installed and signature verified; its Mach-O UUID matched the final release executable, `1AE52A3C-B7FB-356A-9C10-13D99547D5F9`. The original validated 0.7 rollback backup remains available.
- At handoff the Mini received Air 62%, mapped both displays to 68%, with both automatic. Source mode **Scheduled**, no live-session ID. Do not mark Air deployment complete based on a staged ZIP or a signed legacy reading.
- At this checkpoint the Air update, physical responsiveness check and keyboard approval were still pending. The following entries record their subsequent verification.

### Paired Air rollout verified, 2 November 2026

The Air installer reported live session `6D430B24-50DF-4A20-B5A3-A2A438728146`. The Mini independently reported the same signed session, source mode/state `live`/`Live`, and an open lid. Air brightness was 62%; both displays were connected and on automatic, mapped to 68%. Samsung reported its last DDC setting and TV its software level. Ambient input was approximately 40 lux / 5413 K. Successive heartbeats advanced the receiver’s accepted-sample count from 14 to 15 with **zero hardware or software brightness writes** since receiver startup. This proves live delivery and idle deduplication, not physical luminance or key-to-screen latency.

A clean relaunch of the unchanged Mini app rejoined the same Air session. At that point macOS still matched the keyboard permission against the old 0.7 code identity, rather than the installed 0.8 executable. Air sync continued independently.

### Physical brightness-change check and keyboard approval, 2 November 2026

- After the user reset this app's Accessibility approval and requested access again, the Mini reported **Keyboard brightness keys ready** and logged an active key listener. This verifies permission and listener startup, not a separate physical Magic Keyboard keypress.
- The user changed brightness on the Air without **Sync Now** and reported that the displays responded almost immediately. The Mini logged DDC writes of 20% and later 100% to the Samsung, with intermediate levels as it ramped up. At the final reading the Air reported 100%, both displays were still automatic, and both mapped targets were 100%.
- The Samsung value is the **last DDC command**, not hardware readback. The TV's 100% was the **applied software level**. The receiver counted 12 hardware and 62 software writes since restart; those are local display adjustments, not network packet counts.
- Not measured in this desk test: precise key-to-screen latency, separate panel luminance, ten-minute Air CPU/battery use, or the live pair's behaviour across controlled lighting changes, sleep/wake and physical tailnet loss. The CPU comparison above is for the Mini receiver with the scheduled Air helper.

### Mini interface build 9: Light desk

The paired-screen menu-bar mark and illustrated native popover replace the sun
icon and number-heavy default view. The upper controls are per-display brightness,
Follow Air and logical disconnect/reconnect. Exact output, mapping, colour and
calibration remain available under Details; source diagnostics are in Desk
details. The Air helper, wire protocol, existing display preferences and pairing
are unchanged.

- The real installed popover exposed the Light desk heading, portrait Samsung,
  Beyond TV, both enabled Follow Air switches and per-display controls. The Mini
  returned to the same live Air session after installation.
- In an isolated native QA window rendering the production SwiftUI, the TV's
  + button moved its software level from 48 to 54 while Samsung remained at 68;
  minus restored 48. Follow Air switched off/on. Disconnecting the TV disabled
  the last-screen disconnect action. Both the TV reconnect and group reconnect
  restored it. The artwork and disclosure controls opened display details.
- The loopback simulation verified sync acknowledgement on a fresh Air reading;
  the isolated no-sender window showed timeout feedback and re-enabled Sync now.
  Light, dark, empty and disconnected fixtures were rendered. The release build
  and 21 core checks passed. The [README preview](../docs/light-desk.png) is an
  isolated fixture, not a capture of private desktop content.
- The previous app and LaunchAgent were backed up by the Mini installer. The
  new locally signed build may require refreshing its Accessibility approval;
  live Air sync and panel controls are independent of that permission.
