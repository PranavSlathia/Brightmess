# Brightness Relay 0.8.0 verification

1 November 2026, M4 Mini, portrait LU28R55 over HDMI and Beyond TV; source is PRSNL (M2 Air). A monitor percentage is not a photometric measurement.

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
