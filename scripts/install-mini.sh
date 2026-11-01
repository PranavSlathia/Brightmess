#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/Brightness Relay.app"
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.receiver.plist"
TOKEN="$HOME/.config/brightness-relay/token"
BACKUP="$HOME/Library/Application Support/Brightness Relay/Backups/$(date +%Y%m%d-%H%M%S)"
cd "$ROOT"
if [[ "${BR_SKIP_BUILD:-0}" != 1 ]]; then
  "$ROOT/scripts/swiftpm.sh" build -c release
fi
mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
STAGE="$(mktemp -d "$HOME/Applications/.brightness-update.XXXXXX")"
STAGED_APP="$STAGE/Brightness Relay.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 755 .build/release/brightness-relay "$STAGED_APP/Contents/MacOS/brightness-relay"
install -m 644 NOTICE "$STAGED_APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
install -m 644 .build/checkouts/SunKit/LICENSE "$STAGED_APP/Contents/Resources/SunKit-LICENSE.txt"
install -m 644 .build/checkouts/swift-atomics/LICENSE.txt "$STAGED_APP/Contents/Resources/Swift-Atomics-LICENSE.txt"
INFO="$STAGED_APP/Contents/Info.plist"
plutil -create xml1 "$INFO"
plutil -insert CFBundleExecutable -string brightness-relay "$INFO"
plutil -insert CFBundleIdentifier -string dev.pranav.BrightnessRelay "$INFO"
plutil -insert CFBundleName -string "Brightness Relay" "$INFO"
plutil -insert CFBundleDisplayName -string "Brightness Relay" "$INFO"
plutil -insert CFBundlePackageType -string APPL "$INFO"
plutil -insert CFBundleShortVersionString -string 0.8.0 "$INFO"
plutil -insert CFBundleVersion -string 9 "$INFO"
plutil -insert LSMinimumSystemVersion -string 14.0 "$INFO"
plutil -insert LSUIElement -bool true "$INFO"
plutil -insert NSHighResolutionCapable -bool true "$INFO"
# This is a local build. Never automatically pick a certificate from Keychain:
# find-identity can list a certificate whose online trust has been revoked.
SIGNING_IDENTITY="${BR_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
mkdir -p "$BACKUP"
[[ ! -f "$HOME/.local/bin/brightness-relay" ]] || cp -p "$HOME/.local/bin/brightness-relay" "$BACKUP/cli"
install -m 755 .build/release/brightness-relay "$HOME/.local/bin/brightness-relay"
[[ -f "$TOKEN" ]] || "$HOME/.local/bin/brightness-relay" token create

mkdir -p "$BACKUP"
install -m 755 "$ROOT/scripts/rollback-mini.sh" "$BACKUP/Rollback Mini.command"
[[ ! -f "$PLIST" ]] || cp -p "$PLIST" "$BACKUP/receiver.plist"
launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.receiver" >/dev/null 2>&1 || true
pkill -TERM -f "^$APP/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1 || true
for attempt in {1..30}; do
  pgrep -f "^$APP/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -f "^$APP/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1; then
  echo "Existing app did not exit; update stopped before replacing it." >&2
  exit 1
fi
[[ ! -d "$APP" ]] || mv "$APP" "$BACKUP/Brightness Relay.app"
mv "$STAGED_APP" "$APP"
rmdir "$STAGE"

# Preserve the user's existing receiver arguments and fallback settings.
if [[ ! -f "$PLIST" ]]; then
  plutil -create xml1 "$PLIST"
  plutil -insert Label -string dev.pranav.brightness-relay.receiver "$PLIST"
  plutil -insert ProgramArguments -json '[]' "$PLIST"
  args=(/usr/bin/open -W -g "$APP" --args menu --token-file "$TOKEN"
        --latitude 26.1 --longitude 91.7 --timezone Asia/Kolkata)
  for ((i=1; i<= $#args; i++)); do
    plutil -insert "ProgramArguments.$((i-1))" -string "$args[$i]" "$PLIST"
  done
  plutil -insert RunAtLoad -bool true "$PLIST"
  plutil -insert KeepAlive -bool true "$PLIST"
  plutil -insert ThrottleInterval -integer 10 "$PLIST"
  plutil -insert StandardOutPath -string "$HOME/Library/Logs/BrightnessRelay-receiver.log" "$PLIST"
  plutil -insert StandardErrorPath -string "$HOME/Library/Logs/BrightnessRelay-receiver.log" "$PLIST"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
if launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
  for attempt in {1..45}; do
    if "$HOME/.local/bin/brightness-relay" status --host 127.0.0.1 2>/dev/null |
        plutil -extract controls.uiBuild raw -o - - 2>/dev/null | grep -qx '9'; then
      print "Light desk receiver build 9 verified."
      break
    fi
    sleep 2
  done
fi
if ! "$HOME/.local/bin/brightness-relay" status --host 127.0.0.1 2>/dev/null |
     plutil -extract controls.uiBuild raw -o - - 2>/dev/null | grep -qx '9'; then
  if [[ -f "$BACKUP/receiver.plist" && -d "$BACKUP/Brightness Relay.app" ]]; then zsh "$BACKUP/Rollback Mini.command"; fi
  print -u2 "0.8 receiver did not start; see $BACKUP"; exit 1
fi
echo "Brightness Relay 0.8.0 (Light desk, build 9) installed. Previous app and launch settings: $BACKUP"
