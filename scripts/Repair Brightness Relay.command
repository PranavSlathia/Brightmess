#!/bin/zsh
set -euo pipefail

MINI_HOST="100.80.130.61"
BIN="$HOME/.local/bin/brightness-relay"
TOKEN="$HOME/.config/brightness-relay/token"
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist"
LABEL="dev.pranav.brightness-relay.source"

fail() {
  echo
  echo "REPAIR FAILED: $1" >&2
  read -k 1 "?Press any key to close."
  echo
  exit 1
}

[[ -x "$BIN" ]] || fail "Brightness Relay is not installed."
[[ -f "$TOKEN" ]] || fail "The private pairing token is missing."
[[ -f "$PLIST" ]] || fail "The source login agent is missing."
[[ "$(plutil -extract ProgramArguments.2 raw -o - "$PLIST")" == "--host" ]] ||
  fail "The login agent has an unexpected format; no settings were changed."

echo "Reading this MacBook's built-in display brightness..."
sample="$($BIN sample 2>&1)" || fail "$sample"
percentage="$(awk -v value="$sample" 'BEGIN { printf "%.2f", value * 100 }')"
echo "Built-in brightness: ${percentage}%"

echo "Sending a signed test update to the Mac mini over Tailscale..."
send_output="$($BIN send "$percentage" --host "$MINI_HOST" --token-file "$TOKEN" 2>&1)" || fail "$send_output"
echo "$send_output"

BACKUP="$PLIST.before-address-repair-$(date +%Y%m%d-%H%M%S)"
cp -p "$PLIST" "$BACKUP" || fail "Could not back up the login agent."
plutil -replace ProgramArguments.3 -string "$MINI_HOST" "$PLIST" || fail "Could not update the login agent."
plutil -lint "$PLIST" >/dev/null || fail "The updated login agent is invalid."
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" || fail "Could not restart the login agent."

echo
echo "REPAIR SUCCEEDED: the MacBook is now relaying to $MINI_HOST over Tailscale."
echo "The 30-minute schedule and pairing token were preserved."
read -k 1 "?Press any key to close."
echo
