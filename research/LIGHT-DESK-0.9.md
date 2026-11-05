# BRIGHTMESS 0.9 · TV inputs and window moves

The Mini owns both features. A TV input is *not* a macOS display connection.
Changing inputs must not call the brightness, display-disconnect, or window APIs.
Moving a window must not send a TV command. The Air protocol is unchanged.

**Desk result:** the user confirmed one-click **Smart TV → Home** and
**Mac mini → HDMI 3** on the iFFALCON TCL G07. See the
[exact input ID and settings](#verified-return-to-hdmi-3-over-wi-fi).
The PS5 port ID was found but that switch was not tested. For general
installation, permissions and rollback, see the [README](../README.md#install).

## What we reused

The ignored checkout of [Universal TV Remote for macOS](https://github.com/devasheeshG/universal-tv-remote-macos/tree/f7e651b89f6a31f377291d95c41a1590de26de79)
is pinned in the research lockfile. Its Android driver and Roman Odyshew's
MIT-licensed protocol code informed the two TLS sessions, RSA pairing proof,
feature negotiation, key events and deep links. BRIGHTMESS uses bounded stream
framing, requires the on-TV code, pins the server's RSA key, and generates its
private key in Keychain; it does not ship the reference app, its accept-all
verifier, or its on-disk private key. No Python runtime, ADB daemon, or new
network listener is installed.

[Rectangle](https://github.com/rxhanson/Rectangle) is the reference for AX
window selection and screen geometry, not a runtime dependency. The Windows
picker reads window titles only on demand, does not persist or log them, and
binds each row to the original accessibility element. The shortcut is not
assigned until recorded. It never uses the Magic Keyboard brightness keys.

## Verify the TCL, without guessing input IDs

1. Open Light desk on the Samsung. Choose **Pair TV**, select the TV you
   recognize, and enter the code into BRIGHTMESS. A key change requires new
   pairing. **Command sent** means a command was transmitted, not that
   the panel changed inputs.
2. With the TV and consoles available, check **Smart TV** (home), **PS5**
   (HDMI 1), and **Mac mini** (HDMI 3) against the TV's own picture/OSD.
   These are source requests, not power controls. If selecting HDMI makes the
   Mac lose its display, the paired TV control remains on the Samsung.
3. If direct HDMI keys are ignored, use the TV's own input IDs. For the
   G07, see the [verified Wi-Fi route](#verified-return-to-hdmi-3-over-wi-fi)
   below; **Open TV inputs** did not work. On other models the chooser can
   be tested, but don't offer it as working until observed. A separate
   diagnostic option, if needed and available, is temporary debugging *on that TV*
   using a trusted network; do not expose ADB to the office LAN if the device
   does not authenticate clients. With an **already authorized** ADB transport,
   run `zsh scripts/tcl-input-ids.sh TV-IP:PORT`. Compare IDs/properties as
   you change ports using the physical remote. Never copy HW numbers from
   another model. Enter the two verified IDs under **Configure HDMI fallback**.
   Disconnect the ADB session, disable debugging on the TV, then retest both
   buttons. Only set a port to **uses input chooser** if that TV actually opens it.
   [TCL passthrough example](https://github.com/falghamdi125/Google-TV-Remote-for-Windows)
   · [BeyondTV field notes](https://github.com/Gathin23/cleanyourtv/blob/main/docs/devices/tcl-beyondtv-rt2851.md#hdmi-inputs).
4. While the TV shows the PS5, bring a normal Mac browser window from the TV
   onto the Samsung. Verify that the PS5 picture does not change. Return to
   HDMI 3; use the configured shortcut in both directions. Check the Air status
   and press a brightness key on the Magic Keyboard. Reapprove the renamed Mini
   app under Accessibility if macOS requires it.

The README image is an isolated fixture, not hardware acceptance evidence.

## Verification on 2 November 2026

The M4 Mini installed and ran bundle build 10. The original build 9 and its
LaunchAgent were restored during an actual rollback; the corrected migration
then started build 10 with the old arguments except for the app path. A fresh
signed live reading arrived from the unchanged Air. The TCL completed physical
code pairing and the Mini reached “remote ready.” The user confirmed that
Smart TV opened Home. On this iFFALCON TCL, **both** direct HDMI keys were
ignored. The TV offered no secure wireless-debugging pairing, so no ADB
connection was opened and no passthrough IDs were guessed. Both port buttons
were initially set to request the same chooser command. Pairing survived the
app relaunch. A Home → Mac mini test on the installed app reported **Command
sent · Smart TV** followed by **Command sent · Open TV inputs**. Neither
message is active-input readback. The user observed Home but **no source
list** on this TCL. The chooser is therefore not a working fallback on this
unit. HDMI 3 was subsequently verified using the input link below.
After the exact app was re-added, macOS
granted Accessibility and the Mini reported **Keyboard brightness keys ready**.

Release build, 25 executable core checks and the debug loopback simulation
passed. Those include fragmented/coalesced TV messages, a fake TV exchange,
wrong proofs/keys, input-link encoding, stale window selection and shortcut
collision. The Swift Testing target was attempted; this CLT lacks the
`Testing` module. The live picker listed a Zen window on the TV with the
Samsung as its destination. A physical move and a full shortcut round trip
were not confirmed in this run. **Keyboard brightness keys ready** is the
listener's status, not proof of a fresh physical keypress on build 10.

### Separate HDMI-CEC test (not part of build 10)

[MacTV](https://github.com/pengchujin/MacTV/blob/b0d7db0b3b83454a1cf8e39d692a9a76f9024139/Sources/CECCore/CECProtocol.swift)
provided a reference for switching back to the Mac over HDMI. On this desk
the TCL's EDID reports physical address **3.0.0.0** and its matching HDMI
transport supports enabled CEC; the Samsung's transport does not. With user
approval a one-off probe sent **one** Active Source frame (`4F 82 30 00`)
from the Mini's already assigned playback address. No power command, PS5
input request, retry, TV setting change, or app installation was involved.
The local controller finished the transmit request, but the user observed
that the TCL stayed on Smart TV Home: **HDMI 3 did not activate**. Do not use
this announcement as a verified “return to Mac” action on this desk. This
result does not establish whether the TV-side CEC setting or another
firmware behavior caused it.

### Verified return to HDMI 3 over Wi-Fi

Two protocols played different roles. The TCL G07 answered a targeted
MagiConnect/T-Cast UDP discovery on 6537 (version 14), identified itself
on TCP 6553, and returned its recent-input list to read-only query `269>>1`.
This was an external research probe, not a new listener or dependency in the
Mini app. Do not treat this vendor discovery channel as proof of device
identity on a shared LAN. Confirm the intended TV before saving a mapping.

The response included the following IDs. These values belong to this set;
query other TVs rather than assuming their IDs match.

| Physical port | Input ID reported by this TV | Tested outcome |
| --- | --- | --- |
| HDMI 3 · Mac mini | `com.tcl.tvinput/.passthroughinput.TvPassThroughService/HW1413744640` | The installed **Mac mini** button sent the mapped input link once. From Smart TV Home, the user saw the Mac desktop appear without using the physical remote. |
| HDMI 1 · PS5 | `com.tcl.tvinput/.passthroughinput.TvPassThroughService/HW1413744128` | ID discovered only. The PS5 was off; its button was not reconfigured or tested with this link. |

For HDMI 3, **Set up → Configure HDMI fallback** now contains the full ID,
with **Mac mini uses input chooser** off. To reproduce the mapping on this
desk, enter the HDMI 3 ID above, leave the PS5 field and switch unchanged,
and click **Save mapping**. From Home, click **Mac mini** (no ellipsis) and
check for the Mac desktop without using the TV remote. The existing paired Android TV
Remote connection sent the passthrough URI; no native MagiConnect switch
command, power event, ADB, or HDMI-CEC was involved. The list already marked
HDMI 3 selected *before* the test, so that flag is not proof of which picture
is visible. Physical observation was the acceptance check.

References: [MagiConnect wire protocol](https://github.com/DusKing1/ha-tcl-tv/blob/main/docs/protocol.md),
[Android passthrough URI API](https://developer.android.com/reference/android/media/tv/TvContract#buildChannelUriForPassthroughInput(java.lang.String)),
and [a remote implementation of TCL input links](https://github.com/falghamdi125/Google-TV-Remote-for-Windows/blob/main/gtvremote/inputs.py).

### Build 11: global shortcuts and action icons

On this Mini, **⌃⌥⌘M** moves the focused window between the two displays,
**⌃⌥⌘1** targets the TV-reported HDMI 1 input, and **⌃⌥⌘2** targets the
previously verified HDMI 3 input. Smart TV Home stays button-only. Edit the
bindings or icons through **Shortcuts & icons** at the bottom of Light desk.
Fresh installs leave keys unassigned until chosen; these were enabled on
this desk at the user's request. No Spotlight setting was changed.

The installed receiver reported all three global registrations, a ready TV
remote with the popover closed, and live Air sync. Its window action recorded
ten presses and ten destination-screen readbacks. The user confirmed the Mac
desktop returned during the HDMI 3 check; the key-specific counter did not
independently attribute that return to a physical keypress. HDMI 1 was
configured from a fresh input-list read, not physically tested with the PS5.
In an isolated window the icon picker and shortcut recorder both updated
the corresponding control. The release build, 25 core test groups and
debug simulation passed; the Swift Testing target could not compile on
this CLT because its `Testing` module is absent.
