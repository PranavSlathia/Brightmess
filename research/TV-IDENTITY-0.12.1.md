# TV identity continuity — Mini 0.12.1 / build 23

## Incident and verified causes

The source controls stayed disabled at “Opening saved TV identity.” The saved
TCL pairing and HDMI mappings were still present; this was not evidence that the
TV had forgotten BRIGHTMESS or that its IP address had changed.

1. `TVIdentity.load` queried the certificate by its requested display label,
   `BRIGHTMESS Android TV Remote v1`. The file Keychain stored certificate labels
   as the subject name, `BRIGHTMESS`. A read-only metadata probe found **zero**
   old-label matches and **42** certificates matching the existing tagged key's
   public-key hash. The false miss repeatedly created certificates for the same
   key. No duplicate certificates were deleted during this repair.
2. The installed builds were ad-hoc signed. Builds 20 and 21 had different
   cdhash-based designated requirements. An update therefore did not preserve
   the identity used for Keychain and Accessibility authorization.
3. The shared asynchronous identity load had no deadline. Reconnect and code
   pairing could remain busy indefinitely while Security awaited approval.
4. A native build-22 trial reached TLS, where initial RSA-PSS authorization
   blocked Network.framework's shared connection queue. A stack sample showed
   Security authorization inside TLS signing; the main thread was idle. The
   build was rolled back to 21 before preparing build 23.

## Repair

- Locate certificates by the tagged private key's **public-key hash**, not its
  display label. Read only metadata/references for lookup. Select a currently
  valid matching certificate.
- Background reconnect never creates a certificate. An authorization failure
  does not become “not found.” Only explicit pairing may create a missing or
  expired certificate; saved pairing is retained until verification succeeds.
- Run local RSA-PSS and PKCS#1 signing authorization on the existing utility
  loader before starting TLS. The random challenge and signatures are discarded;
  app code does not export private-key data. This moves the observed initial
  authorization wait away from the shared network queue, not a guarantee that
  macOS can never block later if the Keychain locks again.
- Bound the identity wait to 30 seconds. Reject late/cancelled connection work,
  retain a completed identity for an explicit retry, and do not let Bonjour
  restart the wait while busy. An OS authorization dialog itself cannot be
  cancelled by this deadline.
- Use an explicitly configured Apple Development signing certificate for local
  installs. Verify its code-signing trust and require a positive online
  revocation result. Refuse silent ad-hoc fallback and refuse updates that do not
  satisfy an existing certificate-signed app's designated requirement.
- A one-time migration from the old ad-hoc app still needs the user's macOS
  approvals. “Always Allow” is a user decision in the system dialog; the installer
  does not change Keychain ACLs or disable security checks. This local development
  signature is not public Developer ID distribution/notarization.

## Verification

- A label-canonicalization regression failed before the lookup fix and passed
  afterward. Tests cover duplicate/expired certificates, no reconnect creation,
  and no replacement after an authorization error.
- A held identity-loader test failed before the deadline fix and passed afterward.
  It covers responsiveness, deadline, cancellation, stale completion, explicit
  retry and Bonjour interference.
- `scripts/swiftpm.sh build -c release`: passed.
- `.build/release/brightness-self-test`: **27 core checks passed**.
- `.build/debug/brightness-relay simulation-check`: passed, including TV identity,
  reconnect, mapping, shortcuts, window retrieval, display recovery and live
  brightness transport. Expected simulated connection-loss errors are followed
  by verified recovery.
- The default CLT cannot import `Testing`. The full suite was instead run with
  `DEVELOPER_DIR=/Applications/Xcode_27.2.app/Contents/Developer
  scripts/swiftpm.sh test --scratch-path .build/xcode-tests`: **38 tests passed**.
- Two different compiled probes signed with the configured identity satisfy the
  installed app's designated requirement. The old ad-hoc build fails it, as
  intended. A staged update passed the actual installer continuity gate.
- Installer validation found and fixed two shell issues before closeout: avoid
  `grep -q`/SIGPIPE when classifying an old signature under `pipefail`, and prefix
  a literal `codesign -R` requirement with `=` rather than treating it as a file.
- The metadata-only native audit still finds **42** matching certificates after
  the repair; reconnect has not generated more certificates.

## Installed state and remaining physical checks

Build **23** was installed at `~/Applications/BRIGHTMESS.app`. The installer
verified the running receiver build and retained rollback at:

`~/Library/Application Support/Brightness Relay/Backups/20261106-001244.f9JZAP`

The previous build-22 rollback was exercised successfully. Air live updates
continued with reading ages under two seconds while build 23 waited for TV-key
approval. The new 30-second deadline produced an actionable error instead of
remaining busy. The saved pairing, Mac mini **HDMI 1**, PS5 **HDMI 2**, Follow
settings, shortcuts and learned calibration were retained.

The initial final-build check still awaited Keychain authorization and renewed
Accessibility approval. A subsequent report said neither Reconnect nor Pair again
worked and no Keychain dialog was visible. Read-only status confirmed Accessibility
was now approved, but the TV identity loader remained blocked.

The build-23 stack sample placed the wait inside `SecKeyIsAlgorithmSupported` for
RSA-PSS, through Security's legacy-key attribute/wrapping path, not the network.
Both buttons shared that pending operation. One exact-process restart retained the
same build/signature and pairing but initially still waited. A narrowly scoped,
metadata-only local audit showed the key's authorization
partitions contained only old ad-hoc cdhash entries, not the current signing team.
The audit makes no signatures, exports no private bytes and never writes ACLs.

During follow-up, the key's metadata gained the signing team's partition and one additional
trusted-app entry. No agent command modified this access control. The running
receiver then reported **`tvRemoteReady: true`**, and a user-triggered Smart TV send
was recorded. Air sync and Accessibility remained healthy. This confirms an
authenticated connection; it does not by itself prove a physical input change or
that approval will persist through every future OS/certificate change.

No TV source command was sent by the agent during these repair checks. Reconnect
reuses the existing TV pairing; **Pair again with TV code** is the separate
code-generating action. Repeated approval requests without checking the dialog's
visibility were insufficient recovery guidance: distinguish a pending OS operation from a visible prompt,
check the exact process and permission metadata, and keep the app responsive while
waiting. The user subsequently confirmed **finding the Keychain dialog on the TV**.
This explains why it was invisible from the Samsung while the TV showed another
input. A follow-up status check still reported TV ready, no connection error,
Accessibility approved and fresh Air readings. The physical HDMI switch result
remains separate from this authenticated-session evidence.

## Prevention

Keep certificate lookup and connection-wait regressions in executable runtime
checks. Treat signing identity continuity as an install gate, not a release-note
warning. Recheck exact installed-path permissions and the authenticated TV session
after replacement; a green build alone is not evidence of physical TV control.

Apple references: [code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements),
[code-signing technical note](https://developer.apple.com/library/archive/technotes/tn2206/).
