# Exact window geometry — 0.12.2 / Mini build 24

## Report and native reproduction

The user showed Aside physically on the TCL, while “Bring to Samsung” was empty
and “Bring to TV” incorrectly offered Aside as a Samsung window.

The read-only `research/WindowGeometryAudit.swift` reproduced the error without
moving a window, reading document titles, or capturing images. For the **same
native window ID 4392 and owner**, Accessibility reported `(0, 0, 1440, 2539)`, but
WindowServer reported `(-1920, 722, 1440, 2539)`. The connected displays were:

- Samsung: `(0, 0, 1440, 2560)`.
- TCL: `(-1920, 722, 1920, 1080)`.

The existing greatest-overlap screen assignment was correct for its input. The
input was wrong: BRIGHTMESS trusted the stale/display-relative AX origin. A
disposable AppKit fixture on the TV reported consistent AX and WindowServer
coordinates, so a global coordinate offset would break already-correct apps.
No offset, process-name special case, or equal-size matching was introduced.

## Fix and safety boundary

`WindowGeometry.resolve` selects a WindowServer rectangle only by exact window ID
and owner PID. A present metadata snapshot with a missing, reused, ambiguous or
invalid record fails closed; it never substitutes a sibling window. If the ID
bridge or metadata service is unavailable, the existing finite AX rectangle is
the limited compatibility fallback, with no heuristic association to another
window. That fallback cannot correct an inaccurate AX origin.

`WindowServerGeometry` reads only ID, PID and bounds through
`CGWindowListCopyWindowInfo`. It obtains the AX window ID through the exposed
attribute when available, otherwise a guarded runtime lookup of the private
`_AXUIElementGetWindow` bridge also used by Rectangle. This private bridge is a
future-OS compatibility risk; it is not an entitlement or a way to bypass
Accessibility. There are no screenshots, recording requests, content reads,
Space moves or new network services.

Inventory takes one WindowServer metadata snapshot per scan. Movement snapshots
read the original window's current rectangle and verify its native ID again.
Picker, Source Deck shelf, focused-window movement, full-screen eligibility and
post-move verification share the corrected geometry path. There is no idle timer.

## Verification

- The native legacy audit failed with the reported wrong-screen result.
- `exactWindowServerIdentityCorrectsAsideOnTV` failed on the old AX-only resolver
  and passed after the fix. Additional tests cover same-sized sibling windows,
  missing/reused/duplicate IDs, missing AX data, invalid rectangles and unavailable
  metadata.
- The executable geometry checks exercise the production `AXDesk.screen` path.
- The production adapter's read-only audit passed on **the user's actual Aside
  window**: resolved to the TV, included from the other display, excluded from its
  own. This is native discovery proof, not proof of a physical move.

Commands:

```sh
DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer \
  scripts/swiftpm.sh test --scratch-path .build/xcode-tests
.build/debug/brightness-relay window-geometry-check
.build/debug/brightness-relay window-geometry-audit --app Aside --screen 'Beyond TV'
.build/debug/brightness-relay simulation-check
scripts/swiftpm.sh build -c release
.build/release/brightness-self-test
```

## Installation and physical acceptance

- Full Xcode Swift Testing suite: **41 tests passed**.
- Release build, **27 core executable checks**, and the expanded runtime
  simulation all passed. The expected simulated transport-loss errors recovered.
- Installed **0.12.2 / build 24** through `scripts/install-mini.sh`, using the
  existing signing identity and enforcing the build-23 designated requirement.
- Rollback backup:
  `~/Library/Application Support/Brightness Relay/Backups/20261106-003835.Ifq4hR`.
- Immediately after replacement, installed status reported TV remote ready,
  Accessibility approved, brightness keys ready and a fresh live Air reading.
  No new pairing or permission reapproval was required.
- The user physically pressed Control + Option + Space on Samsung, selected
  Aside, and confirmed: **“Aside appears and moves to Samsung.”** This qualifies
  the reported browser-window retrieval, not every application's full-screen
  behavior or every future macOS release.
- A post-move read-only audit found the **same window ID 4392** at
  `(0, 11, 1440, 2539)` on Samsung, now agreed by AX and WindowServer. The installed
  picker reported **one successful move**; TV ready, Accessibility, keyboard
  controls and live Air sync remained healthy.
- The agent's disposable AppKit fixture was terminated after the read-only
  geometry comparison. No user documents, TV input settings, or display
  arrangement were changed by the agent.

## References

- [Rectangle's AX window ID declaration](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Rectangle-Bridging-Header.h)
  and [AccessibilityElement](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift).
  The guarded bridge and resolver are original BRIGHTMESS code, informed by this
  approach; no upstream source module was imported.
- [Apple WWDC19, window metadata and privacy](https://developer.apple.com/videos/play/wwdc2019/701/?time=1007).
  Bounds and unique identifiers are metadata; this implementation does not request
  window names or image capture from Core Graphics.
