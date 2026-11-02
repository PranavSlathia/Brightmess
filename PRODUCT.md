# BRIGHTMESS

## What Source Deck is for

Pranav's M4 Mac mini drives a portrait 28-inch Samsung and a 43-inch
iFFALCON TCL TV. The M2 MacBook Air supplies room and brightness readings.
From the Samsung's menu bar, Pranav should be able to bring back a browser
window or return the TV to his Mac desktop. Those are different requests:

| Action | What changes | What stays alone |
| --- | --- | --- |
| Adjust brightness or **Follow Air** | The selected screen's Mac output. The Samsung uses hardware brightness; the TV uses a software shade. | The TV source and the arrangement of Mac windows. |
| **Bring a window here** or **All windows…** | One specific, eligible window moves to the display where Source Deck opened, without first focusing its app. | Other windows and the TV input. |
| **Smart TV** or **Mac mini** | The paired TV is asked to show Home or the mapped HDMI input. | Mac window positions, display connection and brightness settings. |
| **Disconnect** | A screen is removed from the macOS layout; the last active screen is protected. | This is not a request to turn the panel off or select another HDMI port. |

## What compatibility means

Keep three facts separate: the TV **advertised** a port, the app **sent** a
command, and someone **saw** the requested picture. The G07 returned an HDMI 3
ID over Wi-Fi, and the user saw the Mac desktop appear from Home. Its HDMI 1
ID was also returned, but that does not qualify the PS5 shortcut. A model name
or an open network port is not enough to promise support for a different TV.
See the [physical test record](research/LIGHT-DESK-0.9.md#verified-return-to-hdmi-3-over-wi-fi).

An appropriate next feature is **Discover inputs**: show the ports reported
by the selected TV, let the user name them, then verify the picture once.
The current app supports saving a mapping; it does not perform that discovery.

## Personal controls

Source Deck lets the user change each action's icon and record global shortcuts
for the window toggle, PS5 and Mac mini. The window toggles between the two
displays independently of the pointer. Smart TV Home stays click-only. Never
claim a shortcut is active when another app owns the keys.

## Future product direction (not implemented)

Package a **Sender** for the computer with a native display or room sensors,
and a **Receiver** for the computer driving the destination displays. For this
desk those are the Air and Mini respectively, not software installed on the
Samsung monitor or TV. Offer a paired installer experience without private ZIPs
or scripts. Add TV platforms incrementally, with per-device capability discovery
and verified input switching before advertising support. No additional brands,
commercial packaging, or TV-side installers are part of the shortcuts release.

## Character

Source Deck puts the paired TV's three source actions first, the shelf of
other-screen windows second, and independent display controls third. Use the
green Desk Plan palette in both appearances. Represent displays using their
oriented macOS desktop bounds, not a stock TV/portrait illustration. The
menu-bar mark must remain legible at 23 × 17 points. Use the original-colour
Glass Firefly there and on the app bundle; do not template-tint the mascot.

## Principles

- Lead with the device and the action, not a dashboard of repeated percentages.
- Keep numbers available for diagnosis. Never promote a last-set command to a
  live hardware measurement.
- Controls act on the display they label. Disconnect means removing a display
  from the layout, not sending a black image or promising electrical power-off.
- Preserve live sync, per-screen learning and the final-connected-screen guard.
- Keep the utility light: render on state changes, not with idle animation.

## Accessibility

Pair device silhouettes with names, use native buttons and sliders with
accessible labels, explain disabled actions, and do not rely on colour alone.
Ask for permissions by task: Local Network for the TV, Accessibility for
window moves and brightness keys. The Air relay works independently of both
Mini controls. Window titles stay local and are not included in telemetry.
