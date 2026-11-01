#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BUNDLE="$DIST/Brightness Relay for MacBook Air"
ZIP="$DIST/Brightness Relay for MacBook Air.zip"
TOKEN="$HOME/.config/brightness-relay/token"

if [[ ! -f "$TOKEN" ]]; then
  echo "Install the Mini receiver first so a pairing token exists." >&2
  exit 1
fi

cd "$ROOT"
"$ROOT/scripts/swiftpm.sh" build -c release
rm -rf "$BUNDLE" "$ZIP"
mkdir -p "$BUNDLE"
chmod 700 "$DIST" "$BUNDLE"
install -m 755 .build/release/brightness-relay "$BUNDLE/brightness-relay"
install -m 755 scripts/restore-air-relay.sh "$BUNDLE/Install on MacBook Air.command"
install -m 755 scripts/rollback-air.sh scripts/measure-relay.sh "$BUNDLE/"
install -m 600 "$TOKEN" "$BUNDLE/token"
install -m 600 scripts/AIR_BUNDLE_README.txt "$BUNDLE/README.txt"
install -m 600 NOTICE "$BUNDLE/THIRD-PARTY-NOTICES.txt"
install -m 600 .build/checkouts/SunKit/LICENSE "$BUNDLE/SunKit-LICENSE.txt"
install -m 600 .build/checkouts/swift-atomics/LICENSE.txt "$BUNDLE/Swift-Atomics-LICENSE.txt"

ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP"
chmod 600 "$ZIP"
rm -rf "$BUNDLE"
echo "$ZIP"
