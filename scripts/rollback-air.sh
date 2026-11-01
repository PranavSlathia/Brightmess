#!/bin/zsh
set -euo pipefail
backup="${1:-$(cd "$(dirname "$0")" && pwd)}"
support="$HOME/Library/Application Support/Brightness Relay"
plist="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist"
[[ -f "$backup/air-backup" && "$backup" == "$support"/Backups/* ]] || { print -u2 'Not an Air backup'; exit 1; }
launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.source" >/dev/null 2>&1 || true
[[ ! -f "$support/brightness-relay" ]] || mv "$support/brightness-relay" "$backup/replaced-helper-$(date +%s)"
[[ ! -f "$backup/helper" ]] || install -m 755 "$backup/helper" "$support/brightness-relay"
if [[ -f "$backup/source.plist" ]]; then
  cp -p "$backup/source.plist" "$plist"
  launchctl bootstrap "gui/$(id -u)" "$plist"
elif [[ -f "$plist" ]]; then
  mv "$plist" "$backup/replaced-source.plist"
fi
print 'Air rollback complete; pairing preserved.'
