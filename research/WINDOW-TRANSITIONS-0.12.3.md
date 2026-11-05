# Window transition recovery — 0.12.3 / Mini build 26

## Report

Terminal resized but stayed on Samsung after selection from “Bring to TV.” The
picker reported “That window closed or is no longer available.” The user could
not recall whether Terminal had been in a full-screen Space or a normal window.
The initial read-only audit still found Terminal on Samsung; it had not closed.

Computer Use refused Terminal access. No alternate UI-control mechanism was used
to operate Terminal or its live sessions. Reproduction therefore used the owned
`Window Test.app` fixture, and Terminal acceptance is a separate user check.

## Native reproduction and causes

The actual production retrieval adapter failed on an owned full-screen fixture:

```text
Fixture before: id=8943, state=fullScreen
Fixture progress: Leaving full screen…
That window closed or is no longer available.
Fixture after error: expected id=8943, current id=8943,
  raw AX=(-1230,1092,540,340), resolved frame=nil
```

The window's logical AX element, process and native ID survived. WindowServer
temporarily withdrew its rectangle while exiting full screen; the compound guard
incorrectly turned this into a permanent closure error.

A rapid reverse-move test exposed another boundary: WindowServer can return an
animation-scaled rectangle, e.g. `(272,172)` while the logical AX size remains
`(540,340)`. Treating this presentation rectangle as a normal window size caused
incorrect resizing. The build-25 trial was rolled back to 24 when this additional
edge was observed. Its rollback retained TV pairing, Accessibility and settings.

Opening the picker immediately after activation can overlap the destination Space
animation too; an unready geometry snapshot must not become the final empty list.

## Fix

- Classify missing geometry for the same live PID/AX element/window ID as temporary
  unavailability. Retain permanent refusal for a closed, minimized or replaced
  window; never substitute another window.
- Retry only reads: up to one second before a move, within the existing eight-second
  full-screen-exit deadline and two-second post-move deadline. Recheck cancellation,
  Accessibility and destination at each retry. No repeated movement or exit commands.
- Reject WindowServer rectangles whose size differs from the logical AX size by
  more than two points. The corrected WindowServer origin remains authoritative
  when sizes agree, preserving the Aside wrong-origin fix.
- Require 300 ms of stable normal geometry after full-screen exit and 200 ms of
  stable destination geometry before reporting completion.
- While a picker scan is opening, retry unreadable standard-window geometry for
  at most 1.5 seconds, with cancellation and a fresh metadata snapshot. No idle
  timers, service, shell process, screen capture or TV-source change is added.

## Tests and evidence

- Native full-screen fixture reproduced the original exact error before the fix.
- The animation-rectangle unit regression failed before size agreement was enforced,
  then passed. Tests also cover transient gaps after exit and after writes, bounded
  timeout without writes, and immediate refusal of permanent closure.
- Final native Samsung full screen → TV → Samsung → TV → Samsung passed. All four
  moves retained **window ID 9166** and restored the logical **540×340** size.
- The fixture-only diagnostic command refuses user apps and multiple fixture
  instances. It exercises the real inventory and retrieval adapter, restricted
  to the fixture process; no Terminal commands or user windows are touched.

## Release and installation

- Final full Xcode Swift Testing run: **45 passed**.
- Final release build, **27 core executable checks**, and the expanded runtime
  simulation passed. Simulated transport-loss errors were expected and recovered.
- Installed **0.12.3 / build 26** with the same verified signing identity. The
  installed app passed strict signature validation and reported the expected build.
- Rollback backup of build 24:
  `~/Library/Application Support/Brightness Relay/Backups/20261106-011429.pKwVKt`.
- Immediately afterward, TV remote ready, Accessibility, Magic Keyboard control
  and live Air sync all remained healthy; no permission reapproval was requested.
- No disposable fixture process remained at handoff. The final attempt to repeat
  the full-screen TV-to-Samsung case found no running fixture and sent no move;
  it is not counted as a final-build native pass. The final Samsung-to-TV and
  repeated normal round-trip evidence above is the verified native scope.
- The user retried Terminal through the picker and confirmed: **“Yes, it moves
  correctly now.”** A subsequent installed-status check reported **two successful
  picker moves**, TV ready, Accessibility approved, brightness keys ready, and a
  fresh Air reading. This confirms the reported Terminal retrieval is working.
  Its original full-screen/normal state remains unknown; the reproduced mechanism
  is not proof of every detail of the original event or all Terminal configurations.

## Reproduction commands

```sh
DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer \
  scripts/swiftpm.sh test --scratch-path .build/xcode-tests
.build/debug/brightness-relay window-fixture-move --screen 'Beyond TV'
.build/debug/brightness-relay window-fixture-move --screen Samsung
.build/debug/brightness-relay simulation-check
scripts/swiftpm.sh build -c release
.build/release/brightness-self-test
```

Native commands require the owned fixture to be open on the opposite screen.
`--full-screen` and `--on-samsung` are fixture startup flags, not user-app automation.
