# Interactive computer-use evidence — 2026-11-06

Scope: production Arrange panel, action row and shortcut editor, hosted in a
separate DEBUG fixture app. Window read/write and shortcut registration adapters
are simulated. This is actual GUI interaction evidence, not real app-window
placement or installed-receiver acceptance.

## Observed using computer use

| Action | Observed result |
| --- | --- |
| Open fixture | Arrange this screen visible; Arrange shortcut Unassigned; simulated writes 0. |
| Click Arrange this screen | Native panel named Arrange Samsung opens with Smart, Equal, Windows, Undo, Refresh and Apply. |
| Select Equal | Equal becomes selected; still a 4-window preview. |
| Open Windows; deselect Zen | Zen unchecked; count and status become 3/4 and Preview only · 3 windows. |
| Press Return | Status becomes Arranged 3 windows; Undo enabled; Done visible. |
| Press Command-Z | Status becomes Restored 3 windows; Undo disabled. |
| Press Escape | Launcher returns; simulated writes exactly 6 (3 Apply + 3 Undo). |
| Use suggested keys | Arrange shows Control-Option-Return both in editor and beside action button. Registration is simulated, not a real global binding. |
| Change Arrange icon to Window | Editor reports macwindow; screenshot shows the action-row glyph changed too. Menu selection needed Return to commit through this automation surface. |
| Clear Arrange shortcut | Editor returns to Unassigned; action-row key label disappears. |
| Record Control-Option-Return | Editor and action-row label show the correct human-readable key combination. |
| Reopen; select Smart; Refresh | New four-window preview; Smart selected. |
| Quit fixture | App inventory no longer includes the fixture; process check finds no BRMFixture. |

After the final refresh, the computer-use tool reported intervening user state
changes. The next observed write count was 10, so that later interval is not
used as proof of preview-only write counts. The earlier controlled sequence
above independently showed exactly 6. Only fixture data could be affected.

## Boundaries

- Installed app was observed at 0.12.3 build 26 initially and 0.12.4 build 27
  later, while main-thread work continued. This side lane did not install either
  build or replace the receiver.
- No personal windows were moved/resized by this fixture. No TV source commands,
  pairing, Keychain access, Accessibility grants or real shortcut claims occurred.
- Real global-hotkey dispatch, actual AX frame acceptance, both physical display
  destinations, display loss and installed-app regression remain release checks.
- Testing used the real native controls, not a web imitation. The fixture code
  is excluded from release builds; its unique bundle identifier cannot select
  the normal receiver startup path.

The only production UI follow-up was updating the existing suggested-key help
text to mention the newly available Arrange shortcut.
