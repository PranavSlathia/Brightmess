#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HOST="${1:-100.80.130.61}"
BIN_DIR="$HOME/Library/Application Support/Brightness Relay"
BIN="$BIN_DIR/brightness-relay"
TOKEN_DIR="$HOME/.config/brightness-relay"
TOKEN="$TOKEN_DIR/token"
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist"
LOG_DIR="$HOME/Library/Logs"
LICENSE_DIR="$HOME/.local/share/brightness-relay"

fail() {
  echo
  echo "INSTALL FAILED: $1" >&2
  read -k 1 "?Press any key to close."
  echo
  exit 1
}

if [[ ! -x "$ROOT/brightness-relay" || ! -f "$ROOT/token" ]]; then
  fail "This pairing bundle is incomplete."
fi

mkdir -p "$BIN_DIR" "$TOKEN_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR" "$LICENSE_DIR"
install -m 755 "$ROOT/brightness-relay" "$BIN"
install -m 600 "$ROOT/token" "$TOKEN"
install -m 644 "$ROOT/THIRD-PARTY-NOTICES.txt" "$LICENSE_DIR/THIRD-PARTY-NOTICES.txt"
install -m 644 "$ROOT/SunKit-LICENSE.txt" "$LICENSE_DIR/SunKit-LICENSE.txt"
install -m 644 "$ROOT/Swift-Atomics-LICENSE.txt" "$LICENSE_DIR/Swift-Atomics-LICENSE.txt"

echo "Reading this MacBook's built-in display brightness..."
sample="$($BIN sample 2>&1)" || fail "$sample"
percentage="$(awk -v value="$sample" 'BEGIN { printf "%.2f", value * 100 }')"
echo "Built-in brightness: ${percentage}%"

echo "Testing the signed Tailscale relay to the Mac mini..."
send_output="$($BIN send "$percentage" --host "$HOST" --token-file "$TOKEN" 2>&1)" || fail "$send_output"
echo "$send_output"

rm -f "$PLIST"
plutil -create xml1 "$PLIST"
plutil -insert Label -string dev.pranav.brightness-relay.source "$PLIST"
plutil -insert ProgramArguments -array "$PLIST"
plutil -insert ProgramArguments.0 -string "$BIN" "$PLIST"
plutil -insert ProgramArguments.1 -string source "$PLIST"
plutil -insert ProgramArguments.2 -string --host "$PLIST"
plutil -insert ProgramArguments.3 -string "$HOST" "$PLIST"
plutil -insert ProgramArguments.4 -string --token-file "$PLIST"
plutil -insert ProgramArguments.5 -string "$TOKEN" "$PLIST"
plutil -insert ProgramArguments.6 -string --interval "$PLIST"
plutil -insert ProgramArguments.7 -string 1800 "$PLIST"
plutil -insert RunAtLoad -bool true "$PLIST"
plutil -insert KeepAlive -bool true "$PLIST"
plutil -insert ThrottleInterval -integer 10 "$PLIST"
plutil -insert StandardOutPath -string "$LOG_DIR/BrightnessRelay-source.log" "$PLIST"
plutil -insert StandardErrorPath -string "$LOG_DIR/BrightnessRelay-source.log" "$PLIST"

launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.source" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" || fail "Could not start the source login agent."

echo
echo "INSTALL SUCCEEDED: automatic sync runs every 30 minutes, and Sync Now is available on the Mac mini."
echo "You can delete the AirDrop pairing bundle after installation."
read -k 1 "?Press any key to close."
echo
