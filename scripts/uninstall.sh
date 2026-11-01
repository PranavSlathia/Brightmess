#!/bin/zsh
set -euo pipefail

APP="$HOME/Applications/Brightness Relay.app"
APP_BIN="$APP/Contents/MacOS/brightness-relay"

for label in receiver source; do
  launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.$label" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.$label.plist"
done

pkill -TERM -f "^${APP_BIN} menu" >/dev/null 2>&1 || true
for _ in {1..20}; do
  if ! pgrep -f "^${APP_BIN} menu" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
pkill -KILL -f "^${APP_BIN} menu" >/dev/null 2>&1 || true

rm -f "$HOME/.local/bin/brightness-relay"
rm -rf "$APP" "$HOME/.local/share/brightness-relay"
echo "Brightness Relay agents, app, binary, and license files removed. The private pairing token and display preferences were preserved."
