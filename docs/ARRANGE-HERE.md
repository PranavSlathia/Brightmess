# Arrange here — BRIGHTMESS 0.13.0 / build 29

This feature began in an isolated lane and is now integrated with committed
window, TV, display-recovery and signing fixes through `7e67dd0`. The installed
build-27 sun mark is preserved; the parent checkout's unfinished colour/layout
redesign is not included. No Air update or TV source change is required.

## Integrated release verification

- 60 Swift Testing cases pass, including the 15 arrangement regressions.
- Expanded executable simulation passes for arrangement, picker, geometry,
  TV identity/recovery/mapping, hardware readback, display recovery and live sync.
- Release build and 27 core executable checks pass. Native light/dark previews
  and icon/Reduce Motion checks pass.
- Arrangement shares `WindowServerGeometry.id` and the verified
  `WindowGeometry.resolve` size-agreement guard. It never reads a transitional
  frame between resize and move in its single native write sequence.
- Native testing caught AppKit enhanced-UI animation accepting a resize but
  losing the following position update. The owned fixture reproduced the exact
  failure; a focused regression went red before the guard was implemented.
  Two new tests now cover the successful batch, restoration and assistive tools.
  The frame batch now temporarily suppresses this per-app animation, restores
  its original state even on error, and does not suppress VoiceOver/Switch Control.
- Three actual owned AppKit windows passed exact/tolerant frame readback and Undo
  on Samsung and TV. The TV fixture first needed raising onto its active Space;
  the unavailable attempts sent no writes. No personal app window was selected.
- The user requested activation of Control-Option-Return on this Mini only.
  New installs still leave the action unassigned until selected.
- Final **0.13.0 / build 29** is installed at `~/Applications/BRIGHTMESS.app`
  with the existing verified Apple Development identity. Strict signature checks,
  Accessibility, Magic Keyboard access, authenticated TV session and live Air
  status remain healthy; no new permission approval was requested.
- Control-Option-Return is saved and successfully registered on this Mini. Other
  shortcut settings match the pre-install snapshot. The computer-use tool's
  app-targeted key injection did not exercise Carbon's global hotkey delivery;
  physical key activation is not claimed as a completed test.
- Final installed computer use opened the real panel, deselected all personal
  windows, selected exactly three disposable windows, applied the Samsung layout,
  observed `Arranged 3 windows`, and verified the test app's actual frame changed
  from `(100,2080,500,340)` to `(12,12,1416,840)` in AppKit coordinates. Undo
  reported `Restored 3 windows` and the original frame returned. All test windows
  and the panel were closed afterward.
- Eight persisted calibration/Follow values, semantic TV pairing/input settings
  and all existing shortcut settings were compared with the pre-install snapshot
  and preserved. TV JSON byte ordering changed, but no decoded field did.

### Rollback

The backup of the known-good build 27, including the original launch configuration,
CLI and a private preference snapshot before enabling the new key, is:

`~/Library/Application Support/Brightness Relay/Backups/20261106-022400.6XJTIR`

Its app signature verifies and receiver plist matches the retained launch settings.
Run its `Rollback Mini.command` to restore build 27. Rollback retains current
preferences; the older app ignores the additional Arrange binding. The later
`20261106-024756.w6ytd8` backup holds the intermediate build-28 trial, not the
recommended recovery version. No destructive rollback rehearsal was run on the
live desk. Source is on `codex/arrange-here-v1`; the parent checkout's unfinished
redesign was not overwritten, and nothing was pushed remotely.

## Direction contract

THESIS: preview the real space a window will occupy before changing the desktop.
The user selected full-screen zone outlines, not a small diagram-only modal.

OWN-WORLD: inherit Source Deck's forest, cream and pear, system typography and
native controls. Zone labels stay readable on unknown desktop backgrounds.

STORY: invoke on the pointer's screen, choose Smart or Equal, exclude windows,
inspect outlines, Apply, then Undo or Done. Nothing moves while previewing.

FIRST VIEWPORT: screen-sized transparent outlines; app-labelled zones; one compact
floating control panel with mode, selectable windows, status and Apply/Cancel.
After applying, outlines disappear and the control panel offers Undo and Done.

FORM: user-pinned Operate extension; code-led; no concept tournament. Existing
Source Deck controls and shortcuts remain. New shortcut is unassigned initially.

FINISH: rendered fixture review, source tests, provenance and an explicit physical
release gate. This is an extension of the existing DESIGN.md, not a replacement.

## Interaction

1. Put the pointer on the display to arrange. Choose **Arrange this screen** in
   Source Deck, or assign **Arrange here** in shortcut settings.
2. Full-screen outlines preview the chosen display's usable area. The small
   floating control bar names the display. The other display is not rearranged.
3. **Smart** considers current window proportions and minimum sizes, including
   main-pane layouts. It does not inspect app contents or infer a browser's page.
   **Equal** gives each selected window an equal-size zone; an unused final grid
   cell is possible when the count does not divide evenly.
4. **Windows** expands a checklist with All/None. Deselecting a window changes only the preview.
   **Refresh** scans again and resets selection to the eligible windows.
5. **Apply arrangement** (Return) performs the changes. **Undo** (Command-Z)
   restores exact, unchanged window identities. **Close** (Escape) exits preview;
   while applying, it becomes **Stop** and preserves verified recovery records.

The suggested new binding is Control-Option-Return, but it starts **unassigned**.
Existing movement and TV shortcuts are preserved. As with other action bindings,
conflicts are rejected, and only successfully registered keys are advertised.

### Native fixture previews

These are generated from the native views with synthetic titles and desktop
backgrounds. They are not screenshots of Pranav's desktop or installed-app proof.

| Display | Light | Dark |
| --- | --- | --- |
| Portrait Samsung | [Full outline](arrange-preview/portrait-light.png) | [Full outline](arrange-preview/portrait-dark.png) |
| Landscape TV | [Full outline](arrange-preview/landscape-light.png) | [Full outline](arrange-preview/landscape-dark.png) |

[Expanded checklist](arrange-preview/expanded-light.png) ·
[Permission recovery](arrange-preview/permission-light.png) ·
[Empty state](arrange-preview/empty-light.png) ·
[Undo result](arrange-preview/result-dark.png)

## Behaviour and safety

- Current desktop, cursor-selected display, normal non-minimized windows only.
- Excluded windows remain untouched; their area is not reserved and may be covered.
- Exact native window IDs and owners; no matching by title or window size.
- Deterministic Smart/Equal proposals with minimum sizes and fixed-window support.
- Refuse infeasible arrangements rather than forcing overlap.
- Explicit per-window writes; bounded readback; stop on failure or changed topology.
- Undo is in-memory and skips windows changed since the verified write.
- A delayed or refused Undo keeps its guarded recovery entries for another try.
- A new Apply replaces the previous one-level Undo; closing the preview does not.
- No minimum-size probing by destructive trial resizing. If an app clamps a size
  not reported through Accessibility, stop and offer Undo/exclusion, rather than
  repeatedly fighting the app.
- No automatic background rearranging, app-content capture, or cloud processing.
- No physical-display power, HDMI source, brightness or pairing changes.

## Source provenance

`ArrangementGrid.swift` adapts pure allocation from Rectangle revision
`0698b04de4349f806beeb2e27b1ef9ab71b537b2`,
`Rectangle/MultiWindow/GridTiling.swift` (MIT).
Removed upstream native writes, cycling state and application retry loop.
Retained bounded arithmetic and dimension constraints. Attribution and full
license are in `ThirdParty/Rectangle-LICENSE.txt` and the shipped notices.
No Amethyst, AeroSpace, Magnet or Moom source is bundled in this first version.

The source review distinguished reusable implementation from reference-only
ideas; it was not an audit of every file in every project:

| Reference | Revision / source | What carries into this feature |
| --- | --- | --- |
| Rectangle | [GridTiling](https://github.com/rxhanson/Rectangle/blob/0698b04de4349f806beeb2e27b1ef9ab71b537b2/Rectangle/MultiWindow/GridTiling.swift), MIT | Adapted allocation only. Full attribution in NOTICE and ThirdParty. |
| Amethyst | [0446397](https://github.com/ianyh/Amethyst/tree/04463970f7e93af2d20a26c9063760fa5cb227f0), MIT | Main-pane/companion layout idea; no imported code or Silica dependency. |
| AeroSpace | [bc6be84](https://github.com/nikitabobko/AeroSpace/tree/bc6be84ab7d6ad60a3661833635912f72707abbf), MIT | Orientation-aware splitting as a reference; no workspace daemon or source imported. |
| Magnet / Moom | Official product documentation | UX references only; no source or assets copied. |

The [MIT license](https://opensource.org/license/mit) permits commercial use and
adaptation with its notices retained. The existing installer copies NOTICE into
the app's resources, so the Rectangle notice is included by that path. This is
component-level provenance, not legal clearance of the entire product. Before
sale, review all other dependencies and distribution obligations too. This
adapter uses a guarded private window-ID fallback already familiar to this
codebase; do not infer Mac App Store eligibility. The later distribution lane
still needs stable signing and notarization.

The per-app enhanced-UI animation guard also follows the design demonstrated by
Rectangle's `AccessibilityElement.performFrameAdjustment`; BRIGHTMESS's small
guard and restoration tests are implemented locally. No system VoiceOver or
Switch Control settings, Keychain ACL or system permissions are
changed by this guard.

## Architecture and integration

- `ArrangementGrid`: small, pinned MIT allocation adaptation; no native calls.
- `ArrangementPlanner`: deterministic proposals in global top-left display
  points, translating the allocator's backing pixels once at the boundary.
- `ArrangementTransaction`: preflight exact frames, one bounded application
  sequence per window, readback, cancellation and guarded one-level recovery.
- `ArrangeNativePort`: isolated AX/WindowServer metadata adapter, no screenshots.
  Refresh only enumerates normal on-screen windows on the current Space.
- `ArrangeModel`: preview-only state machine and fixture-test seam.
- `ArrangePanel`: transparent outline surface plus a separate native control bar.

The native port is separate to avoid overwriting the main thread's in-progress
window-identity/full-screen fixes. During integration, reconcile or share the
adapter only after those fixes are committed and their tests still pass.

## Initial isolated verification — 2026-11-06

On branch `codex/arrange-here-v1`, base `b8f5094`:

- Swift Testing: **30 passing tests**, including **13 arrangement regressions**.
- Native model fixture check: preview performs zero writes; selection, modes,
  Apply, Undo, topology invalidation and denied access pass.
- Existing executable simulation: source shelf, shortcuts, live relay, fades,
  ordering and transport recovery pass using fakes/loopback, not physical devices.
- Release build: passed. Executable core self-test: **25 checks passed**.
- Native fixture views: portrait/landscape, light/dark, checklist, empty,
  permission and result states rendered. Review is in [REVIEW.md](arrange-preview/REVIEW.md).
- No installed app replacement, Accessibility changes, live window moves, TV
  commands, installed-app signing changes, commit or push were performed by this
  feature lane.

Follow-up computer-use test: [interactive evidence](arrange-preview/COMPUTER-USE.md).
This uses a separate ad-hoc-signed DEBUG fixture bundle, not a replacement for
the installed receiver. No installed app signing or permission was changed.

Reproduce from this worktree using Xcode's developer directory:

```sh
DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer scripts/swiftpm.sh test --scratch-path .build-arrange
DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer scripts/swiftpm.sh build -c release --scratch-path .build-arrange
.build-arrange/release/brightness-self-test
.build-arrange/debug/brightness-relay arrange-check
.build-arrange/debug/brightness-relay simulation-check
.build-arrange/debug/brightness-relay arrange-preview docs/arrange-preview
```

For repeatable GUI interaction tests, `script/build_and_run.sh` prepares and opens
`dist/BRIGHTMESS Arrange Fixture.app`. The project Run action targets this fixture,
not the production receiver. `--prepare` stages it without launching; `--verify`
checks fixture process startup. The bundle identity activates a DEBUG-only path:
production controls use simulated windows and an isolated temporary preference
suite. It does not create a receiver, network session, real AX window driver or
global key registration. Its process name is `BRMFixture`, so restarting it cannot
kill the installed `brightness-relay`.

## Release boundary and integration history

Source and fixture checks do not qualify all app behaviour. Physical checks must
cover portrait/landscape, mixed scaling, app size clamps, current Spaces,
disconnection, cancellation, Undo after user edits and unrelated TV/Air controls.
The integrated version uses the stable-signed receiver pipeline. The original
older-base build was not installed over the live app.

Integration checklist:

1. Integrate the additive files and the small shortcut/popover hooks with the
   main lane's current picker, TV identity and stable-signing changes; preserve
   its uncommitted work. Do not replace whole files with this older baseline.
2. Re-run the integrated suite and update the shipped third-party notice. Remove
   any older note claiming Rectangle source is not bundled, if present there.
3. Test with disposable windows on both displays: normal Terminal, browser,
   fixed-size window and minimum-size clamp; mixed scaling and Space changes;
   disconnect/cancel during application; Undo after a manual change.
4. Verify pointer-based destination and keyboard operation with the signed app,
   then regress TV input shortcuts, window picker and Air brightness sync.
5. Use the integrated stable-signed installer with rollback; never the original
   branch's pre-integration ad-hoc installer. Final installation is recorded above.
