# Brightness Relay

Brightness Relay is a small native macOS menu-bar controller for a Mac mini
with multiple external displays. It gives each display its own slider,
automatic/manual mode, real disconnect/reconnect, keyboard brightness keys,
per-screen calibration and independent adaptive white balance.

Automatic mode follows the final brightness chosen by a nearby MacBook Air —
including macOS ambient-light decisions and your manual corrections. The Air
sends changed values live over Tailscale. A 60-second heartbeat keeps a quiet
Air fresh; Sync Now still works. The Mini holds the last level for five minutes
on loss, then uses solar fallback. Legacy scheduled helpers retain their longer
freshness window.

The relay reads ambient lux and colour temperature from the Air, then computes
its own True-Tone-like correction for each screen. It does not copy Apple's
complete internal True Tone transformation. Colour starts Off per display.

**Verified on the two-Mac desk, 2 November 2026:** changing brightness on the
M2 Air made the Mini's displays follow without **Sync Now**. The tester described
the response as almost immediate. The receiver logged Samsung DDC settings down
to 20% and back to 100%; the TV followed through software dimming. This was a
physical responsiveness check, not a timed latency measurement. See the
[0.8 verification record](research/IMPLEMENTATION-0.8.0.md) for test results,
CPU measurements and checks that remain open.

## Current two-display behavior

This machine has been probed per display rather than treating every DDC service
as one monitor:

| Display | Stable identity | Brightness path | Displayed reading | Screen off |
|---|---|---|---|---|
| Samsung `LU28R55` (portrait) | EDID `4C2D1610-…` | Targeted hardware DDC write | `Last set` because this unit returns an invalid DDC read stream | Disconnect/reconnect |
| `Beyond TV` 43-inch 4K | EDID `63185128-…` | Per-screen software dimming; DDC read/write rejected | `Software live` | Disconnect/reconnect |

The distinction is deliberate. A cached command is never presented as a live
hardware read. The TV's software value is live because Brightness Relay owns
the shade opacity. The Samsung's hardware backlight target is labeled **Last
set** because the monitor does not provide a checksum-valid readback on this
connection.

**Disconnect** removes a screen from the macOS layout for this login session.
Its card remains available for **Reconnect**. The last active screen cannot be
disconnected. A recovery ledger is saved before the operation; restarting the
app or running recover-displays reconnects recorded screens. Logical disconnect
does not promise electrical power-off.

## Menu-bar controls

Click the sun icon to open the controller:

- one independent brightness slider per connected display;
- **Follow automatic** per display; dragging a slider changes only that display
  without disabling automatic following; an explicit off switch stays manual;
- **Disconnect / Reconnect** per display;
- **Reconnect All** recovery action;
- **Off / Adaptive / Manual white balance**, strength and trim per screen;
- automatic per-screen learning, Undo last match and confirmed Reset calibration;
- Magic Keyboard brightness keys (Accessibility permission required);
- **Re-detect** to retry DDC and refresh monitor readings;
- source status for MacBook Air or solar fallback;
- on-demand Air sync and receiver-log access.

Automatic updates never overwrite a display left in manual mode. Re-enabling
**Follow automatic** applies the current source value immediately.

## White balance and calibration

The Air must be awake and open and is trusted whenever reachable, regardless of
location. Live mode listens for built-in brightness notifications and uses a
two-second watchdog and cached ambient sensor. Only material changes, Sync Now,
lifecycle events and a 60-second heartbeat are sent. One request is in flight;
the newest pending sample wins. No DDC writes are needed on a steady input.
Use `source --sync-mode scheduled --interval 1800` for the old schedule.

Each monitor resolves its own EDID primaries and baseline colour table.
Unknown primaries use a labelled sRGB estimate. Adaptive corrections ease toward
the new target. Missing, closed-lid, too-dark and expired readings restore the
owned baseline. Live colour expires after 90 seconds; scheduled colour expires after 45 minutes. The menu distinguishes
an old Air helper from an unavailable sensor.

Manual white balance accepts 3500–7500 K targets. Reset restores the baseline.
Colour pauses during active HDR or interference from another colour-control
app. API readback verifies the table, not physical colour accuracy.

With Follow automatic on, adjust a screen to a comfortable level. Releasing
its slider, or finishing a group of keyboard presses, learns one match to the
fresh Air percentage and leaves Auto on. The newest match wins; other points
form a monotonic curve. No learning from stale input, solar fallback, fades
or reconnects. Undo/reset are independent per screen. "Mapped target" is not
a hardware measurement: Samsung shows its last DDC command and TV its applied
software level. Optional Samsung extra dimming applies only at hardware zero.

Keyboard keys adjust both connected displays. Plain keys use 6% steps; Option+Shift uses 1%. The menu's Enable button requests
Accessibility permission. Approve Brightness Relay in macOS settings.

Reused components include TrueTone's colour/calibration maths, LuxCurve filtering
and MediaKeyTap. MonitorControl, mac-utils, LumenShift, ddc-mirror and LunarSensor
provided architecture references. No encrypted Lunar code or competing apps are
bundled. See NOTICE and research/repos.lock.json.

## Architecture

```text
MacBook ambient-light / automatic brightness
        ↓
DisplayServices brightness sample (0...1)
        ↓  HMAC-SHA256 authenticated Tailscale request
Mac mini receiver + per-display coordinator
        ├─ Samsung LU28R55 → targeted DDC VCP 0x10
        └─ Beyond TV      → per-screen software shade

Live Air unavailable for 5 minutes
        ↓
SunKit solar elevation, refreshed every 5 minutes
        ↓
Same per-display automatic/manual policy
```

Display routing is keyed by EDID identity, not enumeration order. The native
transport reuses the per-display `IODisplayLocation` →
`IOMobileFramebuffer` → `DCPAVServiceProxy` mapping and MCDP29xx HDMI handling
from [m1ddc](https://github.com/waydabber/m1ddc). DDC packet handling,
serialization, and the software-shade approach follow
[MonitorControl](https://github.com/MonitorControl/MonitorControl). Both are
MIT-licensed and attributed in [NOTICE](NOTICE).

The relay sends no screen content, sensor history, or Apple-account data. A
shared 256-bit token authenticates updates, pull requests, and recovery
controls. Packets older than 30 seconds and repeated nonces are rejected.

## Install

On the Mac mini:

```sh
# From the repository root:
./scripts/install-mini.sh
```

The installer builds and installs `~/Applications/Brightness Relay.app`, then
restarts its LaunchAgent. It preserves the existing relay token and MacBook
pairing.

For a first-time Air installation, copy the Mini's token to
`~/.config/brightness-relay/token` on the Air, then run:

```sh
./scripts/install-air.sh 100.80.130.61
```

Or create the private AirDrop bundle:

```sh
./scripts/create-air-bundle.sh
```

Keep **Automatically adjust brightness** enabled on the Air. The Air source
runs in live mode while that user is logged in and keeps an outbound
long-poll open for **Sync Now**.

The installed fallback coordinates are `26.1, 91.7`, timezone `Asia/Kolkata`.
Update the Mini LaunchAgent arguments if the desktop moves.

## Diagnostics and recovery

```sh
brightness-relay displays
brightness-relay probe
brightness-relay set-display 1 50
brightness-relay wake-all
brightness-relay show-menu
```

`displays` shows stable identities and advertised standby support. `probe`
attempts read-only live DDC reads. `set-display` targets one display; it will
fail honestly for a monitor that rejects DDC instead of claiming success.
`wake-all` asks the running app to reconnect known disconnected screens.
`show-menu` opens the controller without hunting for the status icon.

## Development

The current CLT SwiftBuild engine has duplicate platform specifications.
`scripts/swiftpm.sh` selects the native engine without modifying system files.

```sh
./scripts/swiftpm.sh build -c release
./scripts/swiftpm.sh run brightness-self-test
```

The self-test runs 21 executable groups covering brightness/colour calibration,
sensor validity/expiry, backwards compatibility, authenticated and replay-safe
packets, keyboard steps and disconnect policy. The Swift Testing suite remains
under Tests/; the current Command Line Tools lacks that testing module.

Version 0.8 diagnostics and update packaging:

```sh
brightness-relay status --host 127.0.0.1
brightness-relay sync-now --host 127.0.0.1
brightness-relay sensor-sample                 # on the Air
brightness-relay send-sample --host 100.80.130.61
brightness-relay recover-displays
zsh scripts/package-air-update.sh
```

The Mini installer backs up the old app and preserves receiver arguments. It
uses local ad-hoc signing by default. Do not auto-select the development
certificate currently in Keychain: macOS rejected it as revoked during testing.
BR_SIGNING_IDENTITY can explicitly select a separately validated identity.
No Gatekeeper settings are disabled.

Ad-hoc builds have a new code identity when the executable changes. If the
Accessibility switch is enabled but the menu still reports missing access after
an update, remove the old Brightness Relay entry, add
`~/Applications/Brightness Relay.app` again, and enable it. A valid, stable
signing identity is needed to avoid this local-build reapproval step.

If the entry is on but the app still reports missing access, reset **only this
app's Accessibility approval** on the Mini and request it again:

```sh
tccutil reset Accessibility dev.pranav.BrightnessRelay &&
  "$HOME/.local/bin/brightness-relay" enable-keys --host 127.0.0.1
```

Approve the installed Mini app, then check `brightness-relay status --host
127.0.0.1` for **Keyboard brightness keys ready**. Keyboard permission is not
required for the Air to send readings.

Historical 0.7 integration evidence:
[research/IMPLEMENTATION-0.7.0.md](research/IMPLEMENTATION-0.7.0.md).

The private Air update ZIP in Downloads contains the pairing token. Transfer it
only to your Air, then run the enclosed installer. Its helper lives in
Application Support rather than depending on the previously missing local-bin
executable. Existing brightness-only helpers remain compatible, but cannot
supply colour readings until updated.

The DDC transport uses private-but-local macOS display services because Apple
does not expose external DDC control through a supported public API. This is a
local passion project, not a Mac App Store target.

## 0.8 verification and rollback

Run `BR_TEST_LOG="$TMPDIR/brightness-relay-simulation.log" ./scripts/swiftpm.sh run brightness-relay simulation-check`
for the debug-only loopback publisher/HTTP/display simulation. No physical
monitor, user pairing token or production preferences are used. Use
`zsh scripts/measure-relay.sh mini` or `air` for a ten-minute CPU sample.

Install the Mini first, then run `zsh scripts/package-air-update.sh` and
privately copy the 0.8.0 ZIP to the Air. Both installers keep backups in
`~/Library/Application Support/Brightness Relay/Backups/`. Run the appropriate
rollback command **from its backup folder** to restore the previous helper
and LaunchAgent. The Air installer verifies a new live session, not merely a
successful copy or scheduled packet. A rebuilt ad-hoc Mini app can require
re-adding it in macOS Accessibility settings.

A separate physical desk sensor is not implemented. Solar fallback estimates
brightness only and never invents an ambient colour reading.
