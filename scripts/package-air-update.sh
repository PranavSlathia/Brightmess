#!/bin/zsh
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/swiftpm.sh build -c release --product brightness-relay
BUNDLE="$ROOT/dist/Brightness-Relay-Air-0.8.0"
mkdir -p "$BUNDLE"
chmod 700 "$BUNDLE"
install -m 755 .build/release/brightness-relay "$BUNDLE/brightness-relay"
codesign --force --sign - --identifier dev.pranav.BrightnessRelay.Source "$BUNDLE/brightness-relay"
codesign --verify --strict "$BUNDLE/brightness-relay"
install -m 755 scripts/restore-air-relay.sh "$BUNDLE/Install on Air.command"
install -m 755 scripts/rollback-air.sh scripts/measure-relay.sh "$BUNDLE/"
install -m 600 "$HOME/.config/brightness-relay/token" "$BUNDLE/token"
install -m 644 NOTICE "$BUNDLE/THIRD-PARTY-NOTICES.txt"
install -m 644 .build/checkouts/SunKit/LICENSE "$BUNDLE/SunKit-LICENSE.txt"
install -m 644 .build/checkouts/swift-atomics/LICENSE.txt "$BUNDLE/Swift-Atomics-LICENSE.txt"
zsh -n "$BUNDLE/Install on Air.command"
ZSTAGE=$(mktemp -d "$HOME/Downloads/.brightness-zip.XXXXXX")
trap 'rm -rf "$ZSTAGE"' EXIT
ditto -c -k --keepParent "$BUNDLE" "$ZSTAGE/Air.zip"
chmod 600 "$ZSTAGE/Air.zip"
mv -f "$ZSTAGE/Air.zip" "$HOME/Downloads/Brightness-Relay-Air-0.8.0.zip"
echo "$HOME/Downloads/Brightness-Relay-Air-0.8.0.zip"
