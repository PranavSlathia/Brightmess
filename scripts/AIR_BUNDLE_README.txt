BRIGHTMESS — MacBook Air source setup

This private bundle is for the Air that supplies brightness and ambient colour
to the Mini. If your 0.8 Air helper is already syncing, keep it: Mini 0.9's TV
input and window controls do not require an Air update or TV pairing on the Air.

Install from this bundle:

1. Install the Mini receiver first. The Air must be able to reach it over
   Tailscale. The TV's local Wi-Fi pairing is separate.
2. On the Air, open the lid and enable Automatically adjust brightness in
   System Settings > Displays.
3. Keep the extracted files together. Open “Install on MacBook Air.command”
   from this folder. For a Mini other than the sample desk, run this in
   Terminal from the extracted folder, substituting its Tailscale IP or name:

     BR_MINI_HOST="<Mini Tailscale IP or hostname>" zsh "./Install on MacBook Air.command"

4. Look for LIVE UPDATE SUCCEEDED. The installer checks that the Mini accepted
   a reading from the new live session. A running background job alone is not
   proof of pairing. After verification, delete this setup folder and its ZIP:
   they contain a private pairing token and must never be published or shared.

The source runs at login. It sends changes and a quiet heartbeat; Sync now
still works from the Mini. No window or TV permissions are needed on the Air.

Installed helper: ~/Library/Application Support/Brightness Relay/brightness-relay
Source log:       ~/Library/Logs/BrightnessRelay-source.log
Rollback:         Run “Rollback Air.command” from the backup folder printed by
                  the installer. This restores the previous helper and agent,
                  when present, and preserves pairing.
