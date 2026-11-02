#!/bin/zsh
set -euo pipefail
backup="${1:-$(cd "$(dirname "$0")" && pwd)}"
support="$HOME/Library/Application Support/Brightness Relay/Backups"
app="$HOME/Applications/BRIGHTMESS.app"
plist="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.receiver.plist"
previous="BRIGHTMESS.app"
[[ ! -d "$backup/Brightness Relay.app" ]] || previous="Brightness Relay.app"
[[ "$backup" == "$support"/* && -d "$backup/$previous" && -f "$backup/receiver.plist" ]] || { print -u2 'Not a Mini backup'; exit 1; }
codesign --verify --strict "$backup/$previous"
if [[ "$previous" != "BRIGHTMESS.app" && -e "$HOME/Applications/$previous" ]]; then print -u2 'Previous path occupied; stopped.'; exit 1; fi
launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.receiver" >/dev/null 2>&1 || true
pkill -TERM -f "^$app/Contents/MacOS/brightness-relay menu" 2>/dev/null || true
for i in {1..30}; do pgrep -f "^$app/Contents/MacOS/brightness-relay menu" >/dev/null || break; sleep 0.1; done
if pgrep -f "^$app/Contents/MacOS/brightness-relay menu" >/dev/null; then print -u2 'App did not exit; restore stopped'; exit 1; fi
[[ ! -d "$app" ]] || mv "$app" "$backup/Replaced-$(date +%s).app"
ditto "$backup/$previous" "$HOME/Applications/$previous"
if [[ -f "$backup/cli" ]]; then install -m 755 "$backup/cli" "$HOME/.local/bin/brightness-relay"; fi
cp -p "$backup/receiver.plist" "$plist"
launchctl bootstrap "gui/$(id -u)" "$plist"
print 'Previous Mini receiver restored. Pairing and display preferences preserved.'
