# True-Tone-like adaptation for Pranav's desk

Assessed locally on 1 November 2026. This is a source assessment and bounded,
read-only hardware inspection, not a deployed colour-sync feature.

Later implementation update: selected components were integrated and installed
as Brightness Relay 0.7.0. See [the deployment evidence](IMPLEMENTATION-0.7.0.md)
for live results and remaining gates. The assessment below records the earlier,
pre-integration state; it is not the current deployment status.

## Recommendation

Extend Brightness Relay with selected components. None of these complete apps
is a verified drop-in solution for the M2 Air → Mini → two-screen arrangement.

- Reuse **TrueTone's ambient CCT reader and white-point model**, after validation
  and hardening.
- Use **MonitorControl's per-display lifecycle and gamma-interference handling**
  as the reference for the Mini.
- Consider **LuxCurve's calibration and smoothing** for independent display
  brightness preferences.
- Keep Brightness Relay's authenticated Tailscale transport.
- Use **LunarSensor as a protocol reference**, not as our production daemon.

Call the result *adaptive white balance* or *True-Tone-like*. It calculates a
correction from room measurements; it does not copy Apple's complete internal
True Tone transformation or change the panels' resolution/gamut.

## Setup: evidence and limits

| Device | Verified state and implication |
|---|---|
| Mac mini M4 | Live system report: Apple M4, macOS 27.0.1 build 26A434. Hosts both external screens. |
| Samsung LU28R55, user-described 28-inch 4K | Online, main display, rotation **270°**. macOS reports a **3384×6016 rendering resolution**, with a 1692×3008 logical workspace. That is a scaling configuration, not evidence the physical panel became 6K. |
| Beyond TV, user-described 43-inch 4K | Online, 3840×2160 signal, 1920×1080 logical workspace, rotation 0°, explicitly identified as a television. |
| Both external screens | Each exposes a 1024-entry gamma table. Read-only `CGGetDisplayTransferByTable` succeeded with 1024 samples. Colour-space names are LU28R55 and Beyond TV. AppKit reported current/potential EDR headroom of 1.0 on both in this configuration. |
| MacBook Air M2 | User-specified source. Present on Tailscale. SSH authentication denied, so its OS, sensor model, actual CCT values and lid/wake behaviour were **not verified live**. |

Readable gamma tables do **not** prove that writes will visibly work or remain
stable. No brightness, gamma, connection, rotation or colour-profile settings
were changed during assessment.

Portrait orientation is not a colour-math obstacle: a per-display RGB correction
does not depend on pixel coordinates. Rotation/reconnect must still invalidate
cached routes. A software correction is not inherently limited by the TV's size.
Apple's separate native laptop-assisted route excludes TVs and covers external
displays up to 32 inches: [Apple documentation](https://support.apple.com/en-us/102147).

Current project documentation and earlier verified desk behaviour distinguish
Samsung hardware DDC brightness from TV software dimming. Those brightness
writes were not repeated here. Neither supplies ambient colour measurements.

## Cloned repositories

All five shortlisted projects plus three supporting projects are in
[repos/](repos/). [repos.lock.json](repos.lock.json) records exact remotes, full
SHAs and commit dates. All upstream working trees are unchanged. Clones/build
products are excluded from the parent repository.

| Project | Commit | Decision |
|---|---|---|
| [SaintD1smas/TrueTone](https://github.com/SaintD1smas/TrueTone) | `4bf513544163` | Best sensor/model starting point; requires multi-display hardening and M2 validation. |
| [alin23/lunarsensor](https://github.com/alin23/lunarsensor) | `d66329e85737` | HTTP/SSE reference; incomplete sensor input and stale-colour defects prevent unchanged adoption. |
| [emin93/ddc-mirror](https://github.com/emin93/ddc-mirror) | `4b7cd5726302` | Useful brightness notifications and display routing; no CCT or cross-Mac relay. |
| [nonml/LuxCurve](https://github.com/nonml/LuxCurve) | `7a6becceb353` | Reuse calibration/filters; whole app targets local brightness and Night Shift. |
| [K-M/LumenShift](https://github.com/K-M/LumenShift) | `b4bd31f19652` | Reuse lid/debounce ideas; does not measure room colour. |
| [alin23/Lunar](https://github.com/alin23/Lunar) | `06950e257471` | Reference only for this build; paid adaptive code is encrypted. |
| [MonitorControl/MonitorControl](https://github.com/MonitorControl/MonitorControl) | `7cfe64500d19` | Strong control/lifecycle reference for two screens; no remote colour-sensor feature. |
| [alin23/mac-utils](https://github.com/alin23/mac-utils) | `3e8688fdf7ba` | Minimal lux diagnostic/fallback discovery; ALS helper has no CCT output. |

## Project assessments

### TrueTone — reuse components, not the whole controller

MIT licensed. Reads lux, CCT in Kelvin and raw channels from an ALS HID event.
Its model partially adapts toward room colour, smooths changes and rejects very
dark readings. The author reports testing an M3 Air with a Xiaomi monitor,
not this M2/Mini/TV desk.

Concrete issues:

1. **One profile drives every screen.** `PanelProfile.forExternalDisplay()`
   selects the first external IOAV service; `DisplayController.apply()` uses
   the resulting gains on all external displays. Samsung and TV need separate
   profiles and user trims.
2. **Brightness targeting assumes one monitor.** `DDCBrightness.listIndex()`
   returns the first non-null display name, falling back to an unqualified
   m1ddc command. Do not reuse that selector for this desk.
3. **Success is not verified.** The gamma-write return code is discarded and
   `tinted` becomes true. UI must not equate attempted writes with success.
4. **Restoration is global.** Initialisation/reset calls
   `CGDisplayRestoreColorSyncSettings()`, affecting all screens. Coordinate
   ownership with other colour/dimming apps.
5. **Sensor validation/lifecycle need work.** Infinite lux passes the model's
   usability check; no sample-age field is carried. The raw client pointer is
   never released, despite the comment implying it can be.
6. **EDID is an estimate, not measured calibration.** TV picture modes can change
   the real response. Use per-screen trim; precise matching needs measurement.

Source: [sensor](repos/TrueTone/Sources/TrueTone/AmbientSensor.swift),
[model](repos/TrueTone/Sources/TrueTone/WhitePointModel.swift),
[profile](repos/TrueTone/Sources/TrueTone/PanelProfile.swift),
[colour writes](repos/TrueTone/Sources/TrueTone/DisplayController.swift),
[DDC selection](repos/TrueTone/Sources/TrueTone/DDCBrightness.swift).

### LunarSensor — protocol reference with confirmed gaps

Provides lux/CCT HTTP endpoints, SSE and mDNS. The shipped colour-reader function
returns `None`; the lux reader reads a local file, not the MacBook sensor.

Actual-function tests reproduced:

- Missing lux returns no fabricated measurement.
- Cached lux expires after 30 seconds.
- Cached CCT has **no expiry**, continuing to emit after source failure.
- Non-finite lux is accepted by the reader layer.

Source inspection also shows colour availability latched only at startup,
all-interface IPv4 binding by default on macOS, and no application authentication.
Do not assume mDNS discovers Tailscale peers. Our explicit peer addressing and
HMAC/replay protection are preferable.

**Correction to initial research:** there is no standalone LICENSE file, but
`pyproject.toml:6` explicitly declares **MIT**. The earlier licensing assessment
was incomplete. Preserve the declaration/provenance if extracting code.
Lunar's receiving CCT support is described by this repository, but was not
verified in a running Lunar app; the public Lunar sensor mode is encrypted.

Source: [server](repos/lunarsensor/lunarsensor.py),
[package metadata](repos/lunarsensor/pyproject.toml).

### ddc-mirror — useful brightness plumbing

MIT licensed. Uses native brightness notifications, per-display IO locations,
individual baseline gamma tables, and wake/hotplug re-enumeration.
The source display must be attached to the same Mac. On the Mini it would need
our remote input. Its user offset is global rather than calibrated per screen.
It has no ambient-colour model. Startup detection performs brightness writes,
so the compiled executable was **not launched**.

Source: [ddc-mirror.m](repos/ddc-mirror/ddc-mirror.m).

### LuxCurve — useful preference learning

MIT licensed. Its monotonic log-lux interpolation, median filter, EMA and
calibration points are reusable for separate monitor brightness curves.
It reads lux only; warmth is a preference mapped from lux through Night Shift.
The platform bridge targets `CGMainDisplayID()`, which is the external Samsung
on this Mini, rather than selecting an Air sensor or remote display.
There is no cross-Mac transport or independent external-white-point backend.

Source: [curve engine](repos/LuxCurve/LuxCurve/Engine/CurveEngine.swift),
[calibration](repos/LuxCurve/LuxCurve/Model/CalibrationCurve.swift),
[bridge](repos/LuxCurve/LuxCurve/Bridge/LCBridge.m).

### LumenShift — useful filtering and lid-state policy

MIT licensed. Has separate on/off thresholds, sustained-change debounce and
closed-lid handling. Its HID wrapper retains the client and reacquires missing
services. It reads lux only, invoking `nightlight` to switch Night Shift.
No room-colour measurement, remote transport or separate Samsung/TV colour
model exists. Its UI state also does not propagate every command failure.

Source: [sensor](repos/LumenShift/Sources/LumenShift/LightSensor.swift),
[engine](repos/LumenShift/Sources/LumenShift/Engine.swift).

### Lunar — useful public references, incomplete source distribution

The public code is MIT licensed and includes useful display, gamma, DDC and
keyboard work. `Lunar/Modes/SensorMode.swift.secret` is encrypted; the README
states the full app cannot be built from this tree. It cannot be our complete
open-source foundation. No attempt was made to access hidden code.

Source: [README](repos/Lunar/README.md),
[display implementation](repos/Lunar/Lunar/Data/Display.swift).

### MonitorControl — best existing control architecture to study

MIT licensed. Provides per-display baseline gamma, shade fallback, gamma
interference detection, hardware routing and brightness keyboard integration.
It synchronises locally attached Apple displays, not this remote CCT source.
Review the relevant abstractions; running it as a second gamma owner would
introduce competing controllers.

Source: [display/gamma handling](repos/MonitorControl/MonitorControl/Model/Display.swift),
[Apple source](repos/MonitorControl/MonitorControl/Model/AppleDisplay.swift),
[Apple Silicon DDC](repos/MonitorControl/MonitorControl/Support/Arm64DDC.swift).

### mac-utils — diagnostic building block

MIT licensed. `ALS.swift` tries an Apple sensor-service helper and falls back to
IORegistry properties. It reads lux, not CCT. Its listener retains one selected
sensor and does not re-resolve on repeated failures. Source compiled here;
that does not verify actual Air readings.

Source: [ALS.swift](repos/mac-utils/ALS.swift).

## Verification

Host: Command Line Tools, Swift 6.4.2. Default SwiftPM engine fails before source
compilation with duplicate platform specifications. `--build-system native`
gets past that failure. No system toolchain settings were changed.

| Check | Result and scope |
|---|---|
| TrueTone native build | App and probes compiled/linked. App not launched. |
| TrueTone upstream suite | Blocked by missing `Testing` module; not a pass. |
| LumenShift build | Blocked by missing `SwiftUIMacros.StateMacro` plugin. |
| ddc-mirror | `make` succeeded; no runtime display writes performed. |
| mac-utils ALS | Source compiled with deprecation warnings. |
| LuxCurve / MonitorControl full apps | Xcode-project builds unavailable; selected toolchain is CLT. |
| LuxCurve isolated upstream tests | Models compiled; tests blocked by missing `XCTest`. |
| Lunar full app | Required implementation absent/encrypted in public source. |
| Direct model harness | **9 functional checks passed**; separately reproduced acceptance of infinite lux. |
| LunarSensor harness | **5 characterizations passed**, including two validation/staleness defects. No server started. |
| Local hardware | Both screens returned 1024 gamma samples. No write test. |
| Air hardware | Not tested: remote authentication denied. |

Reproduce bounded checks:

```sh
cd "/Users/pronav/Documents/BRIGHT NESS"
zsh research/run-color-math-checks.sh
python3 research/check_lunarsensor.py
```

The direct harness compiles alongside unmodified upstream model files. It checks
neutral white, different CCT at equal lux, reset, rejection of dark readings,
panel-dependent gains, two-point brightness calibration, 2001 monotonic bounded
interpolation samples, uncalibrated output and rejection of a brief bright spike.
It does not replace the blocked upstream suites or visible-screen verification.

## Integration path and remaining gates

1. **Read-only M2 sensor test.** Compare warm/cool lighting at similar brightness.
   Validate finite values, plausible range, sample freshness, lid state and wake
   recovery. An Air in a different room is not a valid sensor for this desk.
2. **Extend the existing signed envelope.** Optional lux/CCT, age and validity
   fields; keep brightness-only helper compatibility. Reject stale colour.
3. **Per-display colour state.** Stable EDID identity, profile, baseline tables,
   strength, trim and enabled state for Samsung and TV independently. Re-resolve
   transient CG IDs after rotation, wake and reconnect.
4. **Separate colour from brightness.** Continue Samsung DDC and TV shade paths.
   Add coordinated software colour control only after each screen visibly
   responds. Test the present SDR configuration first; HDR needs its own test.
5. **Keep the 30-minute brightness preference.** Do not silently import
   upstream sub-second polling or two-second network events. Offer colour
   cadence separately; change-triggered, rate-limited updates would feel more
   responsive, but that choice remains open.
6. **Honest offline fallback.** Show colour data as unavailable after expiry,
   with an explicit hold/neutral policy. Solar timing cannot measure a lamp's
   colour.

Acceptance must cover both displays independently, reset to baseline, repeated
wake/rotation without accumulating tint, source expiry and manual overrides.
An API success/readback is not sufficient proof of a visible colour change.

## Existing project prerequisite

The installed app was not updated. The workspace has unfinished
keyboard/disconnect work: `MenuBarApp.swift` calls `setBlackout`/`wakeAll` and
reads `isBlackout`, while `DisplayCoordinator.swift` now uses connection states
and reconnect operations. New keyboard-model methods are referenced but not yet
defined. This is a source-level mismatch, not a runtime failure introduced by
this assessment. Reconcile that work and get a clean app build before colour
integration.

**Decision:** selected components are suitable for a prototype, with M2 colour
sensing and visible per-monitor colour application as the next unproven gates.
No exact Apple True Tone equivalence is claimed.
