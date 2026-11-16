#!/bin/zsh
# Build-only: no installed app, permissions, TV input or real window is changed.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_27.2.app/Contents/Developer}"
BUILD="${BR_BUILD_PATH:-$ROOT/.build/feature-tests}"
for name in BRMFixture BRMMoveFixture; do
  if pgrep -x "$name" >/dev/null; then
    print -u2 "Close the owned $name fixture before rebuilding; no running app was replaced."
    exit 1
  fi
done
"$ROOT/scripts/swiftpm.sh" build --scratch-path "$BUILD"
for kind in arrange move; do
  if [[ "$kind" == arrange ]]; then
    app="$BUILD/BRIGHTMESS Arrange Fixture.app"; bin=BRMFixture
    mkdir -p "$app/Contents/MacOS"
    install -m 755 "$BUILD/debug/brightness-relay" "$app/Contents/MacOS/$bin"
    install -m 644 Tests/Fixtures/ArrangeAppInfo.plist "$app/Contents/Info.plist"
  else
    app="$BUILD/BRIGHTMESS Move Fixture.app"; bin=BRMMoveFixture
    mkdir -p "$app/Contents/MacOS"
    xcrun swiftc Tests/Fixtures/MoveWindow.swift -o "$app/Contents/MacOS/$bin"
    install -m 644 Tests/Fixtures/MoveWindowInfo.plist "$app/Contents/Info.plist"
  fi
  codesign --force --sign - "$app"
  print "$app"
done
