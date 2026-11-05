# Bring Here implementation and verification

5 November 2026 · Mini 0.12.0, build 21.

## Implemented

The selected compact native picker is integrated into BRIGHTMESS. A once-only
default offers Control + Option + Space through the existing exclusive hotkey
registration. The shortcut remains editable and removable; old TV and move
bindings are preserved. Source Deck also has an Open window picker action.

Letter groups retain exact window IDs, numbered choices disambiguate duplicates,
search uses a separate text-entry mode, and Left/Right changes destination.
Tab/Shift-Tab and arrow selection agree. Recovery controls retain native keyboard
handling, and selection is exposed through Accessibility with announcement
requests. VoiceOver delivery itself still needs a human check.

The native adapter uses the selected Accessibility element, not current focus.
It revalidates ownership, state and destination, checks full-display geometry
before asking to exit full screen, waits for a settled normal window, fits it
and verifies the resulting display. Cancellation checks separate every mutation,
including the final resize. Unsupported/partial-display full-screen windows
remain visible with a manual-exit explanation.

The API calls follow Apple's per-element [attribute setter](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)
and capability checks; a successful set is not used as proof of final position.
There is no new TV command, network service, private Spaces API or idle polling.

## Automated and rendered evidence

- A first selector test was observed failing against an empty implementation,
  then passing after grouping preserved exact window IDs.
- Seven focused core tests cover duplicate initials, identity, portrait fitting,
  full-screen settling, refusal, timeout, relocation and cancellation.
- The complete Swift Testing run passed **38 tests** using Xcode 27.2.
- The release build and **27 executable core checks** passed.
- Expanded executable runtime simulation passed, including the real picker
  model with fake adapters, older shelf, hotkey migration/collision/repeat,
  TV mapping/reconnection, display recovery, Air live sync, calibration and fades.
- Eighteen production AppKit fixture captures cover apps, multiple windows,
  search, empty, permission, blocked, working, reverse and overflow in light/dark.
  Source Deck light/dark captures also show the new entry point.
- Independent review initially found keyboard recovery, cancellation and
  selection-announcement issues. Its verdict scored all three fixes resolved
  at source/render scope. Documentation preserves the existing design tokens.

Fixture captures and tests are not real AX/Spaces or physical TV acceptance.

## Installed state

Build 21 was installed with a rollback backup after passing checks. Its signed
bundle verifies. The receiver reports uiBuild 21; the new picker shortcut and
existing Control–Option–Command M/1/2 bindings are registered. A fresh signed
live Air sample was accepted after restart. Samsung and TV remain connected,
Follow enabled, with 3 and 2 calibration points respectively. The Air session
and TCL HDMI assignments are unchanged.

The receiver LaunchAgent and Air pairing token are byte-identical to their
pre-update copies. Additional old disconnected display cards are recovery data,
not targets for this feature; no recovery ledger was cleared.

macOS revoked Accessibility approval for the replacement executable and asked
for access to the existing TV Keychain identity. Both were handed to the user.
At this record's initial save, real-window and TV reconnection checks are pending
those approvals; no source command or real window move has been performed for
acceptance. Do not call native retrieval or full-screen Zen qualified yet.

## Backups

- App, CLI, LaunchAgent and standalone rollback script:
  `~/Library/Application Support/Brightness Relay/Backups/20261105-224652.9rhKMJ`
- Additional pre-update preferences, token and LaunchAgent:
  `~/Library/Application Support/Brightness Relay/Backups/BringHere-build20.DQ8bbX`

The backup app signature and rollback script syntax were checked. Rollback was
not executed in this update. Earlier unrelated worktree changes were preserved;
this feature was not committed together with them or pushed.

## Remaining native acceptance

Verify the global trigger from another app, real normal-window movement in both
directions, exact selection among multiple windows, focus restoration on Escape,
and keyboard access to recovery. Then qualify a full-screen Zen window and
confirm the PS5 picture stays uninterrupted while retrieving a Mac window.
Check renewed Magic Keyboard permission and the authenticated TV connection.
No Samsung HDMI qualification is resumed by this feature.

## Permission and live follow-up

After the user reported both approvals, the already-running process still
reported Accessibility denied. One scoped restart of the exact installed
receiver picked up approval: `windowAccessibility` became true and the Magic
Keyboard handler reported ready. No TCC reset or permission modification was
performed by the agent.

The user then physically pressed Control + Option + Space on the Samsung and
reported that the real picker opened. The installed handler's press counter
advanced to 1. A subsequent status reported one successful real retrieval;
the user identified it as the disposable test window and confirmed that it
moved correctly to the Samsung. This verifies the physical trigger and one
real retrieval, not every application or full-screen Zen. The disposable app
was then closed through its own Close test control, and was absent from the
running-app inventory afterward.

A disposable `Window Test` app was created under `.build` for native tests;
its source is retained in `research/bring-here-native-test`. It owns one window
and has no Accessibility automation, global keys or network service. Automated
key injection did not trigger the global handler and instead activated the test
window's focused full-screen button, so it was not counted as a global-key pass.
Later native capture failed with ScreenCaptureKit error -3811; no failed capture
was accepted as evidence of a window's location.

The TV still reported identity authorization pending after the follow-up approval.
A one-second stack sample of BRIGHTMESS located the wait in Security's signing
request, reached from `TVIdentity.createCertificate`; it did not establish a
network failure. The protected SecurityAgent UI was left to the user. Pairing,
certificates, key ACLs and security settings were not reset or changed.

At follow-up closeout, Accessibility and Magic Keyboard handling are confirmed
ready and Air readings remain live. TV reconnection still awaits Keychain
authorization despite the user's reported approvals; no TV-source acceptance
or universal full-screen support is claimed from this session.
