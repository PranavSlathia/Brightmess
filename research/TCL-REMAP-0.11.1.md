# Cable reshuffle · TCL mapping fix · 4 November 2026

## Report and red signal

After a desk move, the user reported Mac mini on TCL HDMI 1 and PS5 on HDMI 2.
The installed build 16 still stored Mac→HDMI 3 and PS5→HDMI 1. A read-only
preferences assertion against the requested assignments failed:

```text
FAIL: saved routes still use previous HDMI 3 / HDMI 1 mapping
```

The source-key subtitles and advanced field placeholders were independently
hardcoded to HDMI 1/3, so changing only the saved input IDs would leave the UI
misleading. The fix stores physical port assignments and derives both labels
and standard key codes from the same data used by buttons and shortcuts.

## Current hardware evidence

The local bounded read-only diagnostic against the selected TV
sends only a TCL identity handshake and read-only query `269>>1`. It installs
no dependency or service and sends no key, input switch, power, ADB or wake
command. The protocol reference is the open-source
[TCL LAN protocol research](https://github.com/DusKing1/ha-tcl-tv/blob/main/docs/protocol.md).
This vendor discovery channel is not an authenticated device-identity proof;
only the existing paired, key-pinned Android remote sends actual actions.

This office TV replied as Smart TV, protocol 14, model `TCL-AP-RTD51A-S1`:

| TV-reported port | Input ID |
| --- | --- |
| HDMI 1 | `com.tcl.tvinput/.passthroughinput.TvPassThroughService/HW1413744128` |
| HDMI 2 | `com.tcl.tvinput/.passthroughinput.TvPassThroughService/HW1413744384` |
| HDMI 3 | `com.tcl.tvinput/.passthroughinput.TvPassThroughService/HW1413744640` |

All custom labels were null. The list marked HDMI 2 selected; that flag is
not physical picture readback. The current TV EDID on the Mini has valid
128-byte-block checksums and HDMI vendor block physical address **1.0.0.0**,
supporting the Mini's direct HDMI 1 connection independently of that flag.
The PS5 assignment comes from the user's cable-layout report, not automated
console recognition or an observed PS5 picture in this run.

## What is dynamic now, and what is not

- **Editable assignment:** Set up → Configure TV inputs… has PS5 and Mac
  mini port pickers. The currently saved TCL catalog fills the chosen port's
  link. Save updates captions and existing shortcuts without sending a TV
  command. It does not need a new app build for the next cable reshuffle.
- **Not automatic identification:** the app does not yet watch CEC topology,
  import input catalogs on its own, or identify an unnamed console. A future
  read-only refresh can suggest the Mac's direct port from validated EDID;
  matching a PS5 needs usable CEC/device labels or user confirmation. Do not
  infer a device from the TV's selected flag or another model's HW numbers.
- A stored catalog belongs to the paired TV only. Re-pairing to a different
  device does not inherit it. Standard HDMI keys remain an advanced blank-ID
  fallback, not a promise; this TCL previously ignored them. Input chooser
  stays available but should not be enabled for this TCL without new proof.

Legacy pairing JSON keeps its original HDMI 1/3 assignments. Changed
assignments preserve the key pin, service name, associated display, icons and
shortcut identities. Invalid/duplicate ports, duplicate IDs, bad URLs and
IDs conflicting with this TV's saved port catalog are rejected without
changing the previous mapping. Fixture saves do not touch real preferences.

## Verification

- `tv-mapping-check` exercises reshuffle captions, exact input links,
  standard fallback keys, legacy decode, persisted assignment/pin/catalog,
  duplicate/invalid mappings, picker independence, save-without-command and
  isolated fixtures.
- Native light/dark panel and mapping-form fixtures are under
  `.impeccable/review/tcl-remap/`. Synthetic window titles only; no fixture
  proves a physical TV switch. Existing Source Deck design is preserved.
- No Samsung input was changed; its physical HDMI tests remain paused.

## Installed acceptance and remaining boundaries

- Installed 0.11.1 / build 17 reports Mac HDMI 1 / PS5 HDMI 2 and their exact
  TV-returned IDs in `controls.tvInputs`. The original preferences assertion
  now passes. Button/shortcut routes use these saved assignments.
- Release build, 27 executable core checks, the full debug loopback
  simulation and 29 Swift Testing tests pass. The fresh Impeccable review
  verdict is ship for the native UI/code paths. Its documenter corrected
  the one fixed-caption sentence in DESIGN.md; tokens and historical
  screenshots were preserved.
- Both display identities, Follow settings, calibration point counts and
  shortcut bindings are unchanged. A fresh signed reading from the same
  live Air session was accepted. TV key pin, service and display association,
  Air token and receiver LaunchAgent arguments compare unchanged.
- Current and backed-up app signatures and rollback script syntax verify.
  App/CLI/LaunchAgent backup:
  `~/Library/Application Support/Brightness Relay/Backups/20261104-162410.HXwDGo`.
  Pre-remap preferences/token/LaunchAgent snapshot:
  `~/Library/Application Support/Brightness Relay/Backups/TCL-remap-build16-20261104.yZbk1Q`.
  A downgrade is not performed against the working desktop merely to test it.
- The ad-hoc replacement needs Accessibility reapproval for brightness keys
  and window moves. No system permission database was reset.
- **Separate connection limitation:** the remote was not ready before this
  update and remains at “Looking for paired TV…” afterward. Direct TCL UDP
  discovery/read-only input query and TCP 6466 are reachable, but bounded
  Bonjour browsing returns no Android TV Remote service. The installed UI
  was inspected and shows the corrected captions plus that discovery status.
  No source command was sent. A TV-side service/network refresh is still
  needed before the newly configured buttons can be physically tested.

Neither new-cable picture switching nor automatic PS5 identification is
claimed as verified. Samsung HDMI qualification stays paused.
