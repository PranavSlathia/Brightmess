# BRIGHTMESS

## What Light desk is for

Pranav's M4 Mac mini drives a portrait 28-inch Samsung and a 43-inch
iFFALCON TCL TV. The M2 MacBook Air supplies room and brightness readings.
From the Samsung's menu bar, Pranav should be able to bring back a browser
window or return the TV to his Mac desktop. Those are different requests:

| Action | What changes | What stays alone |
| --- | --- | --- |
| Adjust brightness or **Follow Air** | The selected screen's Mac output. The Samsung uses hardware brightness; the TV uses a software shade. | The TV source and the arrangement of Mac windows. |
| **Bring [app] here** or **Choose window…** | One eligible Mac window moves to the monitor where Light desk was opened. | Other windows and the TV picture source. |
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
Build 10 supports saving a mapping; it does not perform that discovery.

## Character

Illustrated, expressive, recognizably native. Show the physical difference
between the two displays; let the screen artwork respond to brightness. The
menu-bar mark must still read as a single silhouette at menu-bar size.

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
