# Paired-TV discovery dead end · 0.11.2 / build 19

## Root cause and reproducible signal

On the reshuffled desk, build 17 showed “Looking for paired TV…” with disabled
source keys. Its reconnect routine required a resolved Bonjour hostname before
even opening the pinned TLS connection. No Bonjour result meant neither a
connection attempt nor useful retry. Setup also hid the familiar TV-code
action behind the discovery list, even though a stored pairing still existed.

The original live check failed:

```sh
brightness-relay status --host 127.0.0.1 | jq -e '.controls.tvRemoteReady == true'
# false, exit 1
```

The same TV answered direct read-only TCL input queries and TCP 6466. Its
live RSA public-key fingerprint matched the saved pairing pin. This ruled out
a changed TV identity as the reason for the initial discovery dead end.
The new native two-second LAN broadcast probe also found no candidates on
this office network; direct unicast still worked. Do not claim the broadcast
fallback will bypass network isolation or always find this TV automatically.

## Change

- Persist a last-host hint only after a pinned remote handshake or successful
  physical code proof. Try Bonjour, then that hint, then a bounded ephemeral
  UDP probe on active IPv4 broadcast-capable LAN interfaces. No address sweep,
  new listener service, Python runtime or shell process per sample is added.
- Probe packets are read-only T-Cast discovery, not remote keys or input
  selection. A name-matching reply supplies an address candidate, never trust.
  Candidate count and payload size are bounded; public/non-TV replies are
  rejected. The original paired TLS pin remains mandatory for reconnect.
- Ignore loss of a Bonjour advertisement while a working TLS session remains.
  Failure recovery never queues an action. Empty searches finish with an
  actionable status; retries back off to 60 seconds. Sleep/closing demand
  cancels in-flight discovery and rejects late results.
- Setup always exposes **Pair again with TV code** for a saved pairing, plus
  inline secure code entry and cancellation. A local-address escape hatch
  can explicitly request code pairing when discovery is blocked. Save the
  new pairing only after the physical code proof; cancellation/failure keeps
  the previous identity and input mappings. No automatic re-pairing occurs.
- **Pairing saved** is distinct from **TV connected**. Preserve TV mappings,
  old shortcuts, Air pairing, display identities and Samsung qualification.

Protocol reference: [TCL LAN discovery research](https://github.com/DusKing1/ha-tcl-tv/blob/main/docs/protocol.md).
The native implementation adapts protocol facts, not an extra remote service.

## Verification

`tv-reconnect-check` uses isolated preferences, fake discovery and connector
adapters while exercising the production recovery decisions. It checks absent
Bonjour, cached/changed addresses, wrong-key rejection, no offline action
replay, explicit code-pairing entry, preservation of saved pairing, sleep,
late callbacks and bounded retries. Added review regressions cover a stale
Bonjour candidate falling back to a distinct cached authenticated address
without requiring broadcasts, and both automatic Bonjour callback paths
leaving an explicit code-pairing lookup uninterrupted. Pure discovery tests reject unrelated
names, public/loopback addresses, non-TV and oversized packets; request bytes
contain no action.

Full debug loopback simulation passes. Full Xcode runs 31 Swift Testing tests.
Release build and 27 executable core checks pass. Production native fixture
captures under `.impeccable/review/tv-recovery/` cover connected, disconnected
setup and empty secure code entry in both appearances. They are synthetic
fixtures, not TV code or physical source-switch acceptance.

The current desk's known address will be seeded as a per-pair locator after
the live fingerprint comparison, not hardcoded into the app. The installed
TLS handshake must independently verify the original pin before success is
declared. Installed results are recorded below after verification.

## First install exposed a blocking Keychain load

The initial build 18 process was alive but not listening on the receiver
port. A native sample placed its main thread inside TVIdentity.load /
createCertificate waiting for the Keychain. The installer correctly rejected
the non-started receiver and actually rolled back to build 17 from
`~/Library/Application Support/Brightness Relay/Backups/20261104-175041.n8eDLK`.
The restored build 17 answered status again; no TV input or pairing code was
sent. This is actual rollback evidence, not a syntax-only check.

Build 19 moves identity loading to a coalesced utility task. Menu and receiver
startup proceed while macOS requests access; cancelled or superseded
connections reject a late identity result. A synchronous fake at the actual
identity-loader seam blocks on the utility thread, allows main-actor
cancellation, then signals completion. The test awaits the connection
preparation task before asserting no TLS start. Temporarily removing the
production post-load generation guard made this check fail with “A late
identity approval revived a cancelled connection”; restoring it passes.
The existing key remains in Keychain; no private key is
exported and no system approval is bypassed.

The same-turn start/cancel regression also awaits the actual attempt and
asserts the loader was never invoked. Guards before and after the load cover
both cancellation windows. The independent reviewer scored the cached-host,
Bonjour/pairing race and identity-wait findings resolved at source/test scope.

## Final installed verification

Final build 19 at `~/Applications/BRIGHTMESS.app` passes strict signature
verification and reports **TV remote ready**, no connection error, and no
source command sent. The original live jq assertion now returns true / exit 0.
The installed app completed its pinned TLS/protocol handshake using the
existing TV key, not a new TV-code pairing. The last authenticated address is
saved per pairing; no office address is compiled into the binary.

The installed receiver accepted a fresh signed Air reading and reported both
screens connected. TV key pin, service/display association, Mac HDMI 1 and
PS5 HDMI 2 links, shortcut bindings, Follow settings and learned-point counts
compare unchanged from the pre-update snapshot. Air token and receiver
LaunchAgent arguments compare byte-for-byte unchanged. No TV source change
or Samsung input test was sent to obtain these results.

The final install's immediately previous app is backed up at
`~/Library/Application Support/Brightness Relay/Backups/20261104-175925.9VByGm`.
The actual tested build-17 rollback remains at
`~/Library/Application Support/Brightness Relay/Backups/20261104-175041.n8eDLK`,
with original settings separately snapshotted at
`~/Library/Application Support/Brightness Relay/Backups/TV-recovery-build17-20261104.bGv2ua`.

The new ad-hoc build still requests Accessibility reapproval for window moves
and brightness keys; TV connection/buttons do not require that permission.
The restored code-entry flow is source/fixture tested, not a new physically
completed pairing in this run. Picture switching on the new HDMI assignments
and paused Samsung qualification remain separate acceptance boundaries.
