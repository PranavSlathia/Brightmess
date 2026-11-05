# Samsung reconnect incident and 0.10.3 fix

## Observed on 3 November 2026

After a logical disconnect and cable replug, WindowServer retained two offline
Samsung slots (`1` and `2`) with identical vendor `19501`, model `4118` and
serial `1129853751`. The old resolver counted both and returned the exact
error: `LU28R55 matches more than one display, so reconnect was refused.`
They had different cached IORegistry port paths, 1×1 bounds, all-zero system
UUIDs, and no current Samsung DCP/EDID endpoint. Direct enable-only recovery
against each identity-checked slot reached commit but macOS returned `1001`.
Neither was reported as successful. The TV stayed online throughout.

Power-cycling the Samsung and reconnecting its cable restored the physical
endpoint. Public enumeration and BRIGHTMESS both reported it connected, but
the old coordinator retained the failed-reconnect text. Later read-only
observations saw the Samsung disappear and return without an app disconnect
event. That is not proof that the app caused the later link loss, nor that a
software identity fix repairs all monitor/adapter handshake failures.

## Change

- Snapshot the private WindowServer slots with cached port and current
  IORegistry EDID evidence. Do not use an offline all-zero system UUID as a
  monitor identity, or treat every cached vendor/model/serial match as another
  physical screen. Deduplicate repeated numeric IDs.
- Prefer matching current endpoints over stale slots. Use the recorded port
  to resolve disabled or otherwise identical candidates. Reject mismatched
  live EDID, reused numeric IDs and genuinely ambiguous targets.
- Resolve before disconnecting. Re-resolve after enabling because macOS can
  allocate a new numeric ID. Already-online recovery skips the enable call.
- Keep recovery records on failed commits and report actionable recovery
  advice instead of success. Avoid rewriting an unchanged ledger on refresh.
- On observed reattachment, clear old connection errors, invalidate output
  cache and restore the current mapped automatic level or saved manual level
  once. Do not learn, change Follow, modify TV inputs or rewrite steady output.
- Keep a known display's card after unexpected physical loss.

## Verification

Before the fix, the executable fixture failed with:

```text
brightness-relay display-recovery-check
error: check("Replug retained the stale ambiguous reconnect error")

brightness-relay display-identity-check
error: Failed(message: "stale offline slot falsely makes Samsung ambiguous")
```

After the fix, both targeted commands pass. The controller fixtures also
exercise new IDs after enable, online no-ops, cloned serials, ambiguous
disconnect refusal, commit failure, bounded retries and recovery retention.
The coordinator fixture covers physical loss, replug, stale errors, output
restoration, Follow/manual preservation, no learning, independent TV and no
steady-target writes. All use fake drivers and isolated files/preferences.

The read-only native check sees two online displays plus one cached offline
slot, resolves both correctly and exercises already-online recovery with a
backend that refuses every configuration write:

```sh
scripts/swiftpm.sh build -c debug
BR_TEST_LOG=/dev/null .build/debug/brightness-relay display-identity-check
BR_TEST_LOG=/dev/null .build/debug/brightness-relay display-recovery-check
.build/debug/brightness-relay display-identity-live-check
BR_TEST_LOG=/dev/null .build/debug/brightness-relay simulation-check
```

The wider loopback simulation passes. The full Xcode 27.2 Swift Testing suite
passes 25 tests, including eight new recovery tests. The default Command Line
Tools cannot import `Testing`; full Xcode was selected per-command, not made
the system default. Explicit ColorSync linkage is needed now that tests
exercise the hardware library's display-UUID fallback directly.

Two initial diagnostic fixture runs used the default log before subsequent
runs were isolated with `BR_TEST_LOG=/dev/null`. Their synthetic 40% writes
and disconnect/failure messages are not physical display operations; do not
use them as evidence of a real Samsung disconnect.

## Installed verification

Mini 0.10.3/build 15 was installed with a signed build-14 app/CLI/LaunchAgent
rollback backup at
`~/Library/Application Support/Brightness Relay/Backups/20261103-140044.YAknPl`.
An additional private state backup retained the token, preferences, recovery
ledger and receiver arguments. The installed signature verifies; the pairing
token and receiver LaunchAgent compare byte-for-byte with the pre-update
copies. Both screens report connected with Follow on and one learned point
each. The same live Air session delivered fresh signed updates; the paired
TCL remote session became ready without sending a TV command. All three
global shortcut registrations and their icons/bindings were preserved.

macOS requires Accessibility reapproval for the replaced ad-hoc-signed app;
keyboard interception and window moves remain unverified until the user
re-enables the exact installed `~/Applications/BRIGHTMESS.app`. No TCC reset
or TV re-pairing was performed. Recovery fixture tests, 25 release core
self-checks, 25 Swift Testing tests, native read-only resolution, the wider
loopback simulation, shell syntax and strict signature checks passed.

**Not performed:** another physical Samsung disconnect/reconnect cycle. The
native check is read-only and cannot qualify that cycle or promise that a
future firmware/cable handshake failure will recover without a power cycle.
