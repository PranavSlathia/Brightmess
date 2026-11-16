#!/bin/zsh
# Isolated native UI fixture. Never installs or restarts the real receiver.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/.build/BRIGHTMESS Preview.app"
BIN="$APP/Contents/MacOS/brightness-preview"
if pgrep -f "^$BIN " >/dev/null; then
  pkill -TERM -f "^$BIN "
  for attempt in {1..30}; do
    pgrep -f "^$BIN " >/dev/null || break
    sleep 0.1
  done
  if pgrep -f "^$BIN " >/dev/null; then
    print -u2 'Preview did not exit; leaving it unchanged.'
    exit 1
  fi
fi
"$ROOT/scripts/swiftpm.sh" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 .build/debug/brightness-relay "$BIN"
install -m 644 Assets/Brand/Compiled/BRIGHTMESS.icns "$APP/Contents/Resources/"
INFO="$APP/Contents/Info.plist"
plutil -create xml1 "$INFO"
plutil -insert CFBundleExecutable -string brightness-preview "$INFO"
plutil -insert CFBundleIdentifier -string dev.pranav.Brightmess.Preview "$INFO"
plutil -insert CFBundleName -string "BRIGHTMESS Preview" "$INFO"
plutil -insert CFBundlePackageType -string APPL "$INFO"
plutil -insert CFBundleIconFile -string BRIGHTMESS "$INFO"
plutil -insert NSPrincipalClass -string NSApplication "$INFO"
plutil -insert LSMinimumSystemVersion -string 14.0 "$INFO"
codesign --force --sign - "$APP"
open -n "$APP" --args panel-preview "$ROOT/.build/deck-preview-offscreen.png" --window --backdrop --tv-remapped "$@"
