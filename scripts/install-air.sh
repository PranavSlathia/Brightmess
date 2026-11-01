#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-100.80.130.61}"
BIN_DIR="$HOME/Library/Application Support/Brightness Relay"
BIN="$BIN_DIR/brightness-relay"
TOKEN="$HOME/.config/brightness-relay/token"
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist"
LOG_DIR="$HOME/Library/Logs"
LICENSE_DIR="$HOME/.local/share/brightness-relay"

if [[ ! -f "$TOKEN" ]]; then
  echo "Missing $TOKEN" >&2
  echo "Copy the Mini's token file there first; do not generate a different token." >&2
  exit 1
fi

cd "$ROOT"
"$ROOT/scripts/swiftpm.sh" build -c release
mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$LOG_DIR" "$LICENSE_DIR"
install -m 755 .build/release/brightness-relay "$BIN"
install -m 644 "$ROOT/NOTICE" "$LICENSE_DIR/THIRD-PARTY-NOTICES.txt"
install -m 644 "$ROOT/.build/checkouts/SunKit/LICENSE" "$LICENSE_DIR/SunKit-LICENSE.txt"
install -m 644 "$ROOT/.build/checkouts/swift-atomics/LICENSE.txt" "$LICENSE_DIR/Swift-Atomics-LICENSE.txt"

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
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "MacBook source installed; syncing every 30 minutes to $HOST with on-demand pull enabled."
