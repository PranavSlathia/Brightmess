# Brightness Relay 0.7.0 integration evidence

Verified on 1 November 2026, Mac mini M4 with the portrait Samsung LU28R55
and Beyond TV. This supersedes deployment-status statements in the earlier
source assessment, not its upstream findings.

## Integrated components

- TrueTone: read-only ambient CCT/lux sampling, white-point maths, per-panel
  chromaticity model and two-anchor brightness calibration; hardened for two
  displays, invalid readings, stale input and restoration ownership.
- LuxCurve: bounded median filtering of three brief sensor samples.
- MediaKeyTap: pinned keyboard-event implementation for brightness keys.
- MonitorControl and other assessed repositories: design references for
  per-display ownership, interference checks, lid/sleep handling and routing.
- Existing HMAC/replay-protected Tailscale transport retained; no competing app
  or encrypted Lunar feature is included. See NOTICE for attribution.

## Build and regression results

- Release build succeeded with the installed CLT 6.4.2 native build engine.
- `./scripts/swiftpm.sh run -c release brightness-self-test`: **15 core groups
  passed**. Includes signed ambient packets, backward-compatible brightness-only
  packets, stale/lid/invalid sensor rejection, replay checks, per-display
  calibration, keyboard steps, last-active-screen guard and colour calculation.
- `./scripts/swiftpm.sh test`: **blocked**, not passed. This CLT installation
  lacks the `Testing` module. Tests remain under `Tests/BrightnessCoreTests`.
- Dim-room regression was first reproduced with the actual controller startup
  pattern: native CCT 6462.19 K, reset to native, intensity 0.65, lux 40, ambient
  5419 K. After 60 updates the old implementation still gave native white.
  Cause: the deadband was applied to remaining smoothing distance. It now
  filters changes to the accepted sensor target, allowing the first subtle
  correction and complete convergence. Tests cover gradual movement, complete
  convergence, noise rejection and zero-strength restoration.

## Live verification

| Check | Observed result |
|---|---|
| Air helper update | User ran the installer on PRSNL; reported an accepted 100% brightness / 5423 K sample and a running background service. |
| Receiver after final Mini restart | Signed Air input arrived, one pull connection active; 41 lux, 5429.5 K, lid open. Brightness remained 100%. |
| Samsung manual colour | 5700 K produced RGB table peaks `[1, 0.94063, 0.82725]`; TV unchanged. Off restored the baseline. |
| TV manual colour | 5500 K produced peaks `[1, 0.89232, 0.76615]`; Samsung unchanged. Off restored the baseline. |
| Adaptive colour, final build | Both screens set Adaptive. Target moved below native, around 6430 K during settling. Independent CoreGraphics readback: Samsung peaks `[1, 0.9976744, 0.9927503]`; TV `[1, 0.9966334, 0.99218]`; 1024 samples each, success results. |
| Logical disconnect/reconnect | TV disappeared from the active display list while its recovery state remained. Disconnecting the last Samsung was refused. TV reconnected and recovery ledger cleared. This is not electrical power-off. |
| Keyboard permission | Settings showed Enabled, but TCC rejected the updated executable against the earlier ad-hoc code hash. User asked to remove/re-add the final installed app. Physical key verification remains pending. |

Samsung retains hardware DDC brightness with honest **Last set** reporting
because live DDC readback is unavailable. TV uses software dimming with live
app-owned opacity. Existing brightness-mode preferences were preserved:
Samsung automatic, TV manual. Both colour modes are Adaptive independently.

## Installation and recovery

Installed at `~/Applications/Brightness Relay.app`, version 0.7.0/build 7.
Final installation backup:
`~/Library/Application Support/Brightness Relay/Backups/20261101-225528`.
Pairing and receiver arguments were preserved. App and source bundle signatures
were verified. The existing development certificate was rejected by macOS as
revoked; the installer defaults to local ad-hoc signing rather than silently
selecting it. Security checks were not disabled.

The Air bundle remains `~/Downloads/Brightness-Relay-Air-0.7.0.zip`. It contains
private pairing material and is excluded from Git. The user's successful Air
installation is sufficient; the final dim-room correction is Mini-side.
Automatic source sends remain every 30 minutes, plus Sync Now. A local one-second
colour interpolation timer does not change the Air's sampling/network cadence.

## Proof boundaries

- Gamma API readback verifies software state, not measured panel colour accuracy
  or an exact match to Apple's proprietary True Tone transform.
- Real warm/cool room transitions, Air lid-close/wake, monitor cable removal,
  HDR operation and competing colour-app recovery were not exercised end to end.
- Native menu visual QA was blocked by the automation tool timing out when
  selecting this accessory app. Code and runtime diagnostics were inspected.
- The keyboard event tap still needs current-executable permission and a real
  keypress check; do not equate the settings switch alone with working keys.
- Stable signing is a remaining distribution improvement. Rebuilt ad-hoc copies
  can require refreshing the Accessibility entry.
