BRIGHTNESS RELAY — MACBOOK AIR SETUP

1. Keep the MacBook and Mac mini on the same Wi-Fi network.
2. In System Settings > Displays, enable "Automatically adjust brightness".
3. Right-click "Install on MacBook Air.command" and choose Open.
4. If macOS asks, allow Terminal to run the file.

The installer verifies that it can read the built-in display, installs a small
login agent, and starts relaying brightness to the Mac mini over Tailscale.
It sends live brightness changes and filtered room readings; Sync Now is still available.

The pairing token in this folder controls the Mini's brightness receiver. Do not
share it. Delete this setup folder and its ZIP after installation.

Logs:
  ~/Library/Logs/BrightnessRelay-source.log

Uninstall:
  launchctl bootout gui/$(id -u)/dev.pranav.brightness-relay.source
  rm ~/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist
  rm ~/.local/bin/brightness-relay
