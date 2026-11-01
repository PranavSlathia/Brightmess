#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/swiftpm.sh build -c release --product brightness-relay
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
install -m 755 .build/release/brightness-relay "$stage/brightness-relay"
codesign --force --sign - --identifier dev.pranav.BrightnessRelay.Source "$stage/brightness-relay"
install -m 755 scripts/restore-air-relay.sh scripts/rollback-air.sh scripts/measure-relay.sh "$stage/"
install -m 600 "$HOME/.config/brightness-relay/token" "$stage/token"
install -m 644 NOTICE "$stage/THIRD-PARTY-NOTICES.txt"
install -m 644 .build/checkouts/SunKit/LICENSE "$stage/SunKit-LICENSE.txt"
install -m 644 .build/checkouts/swift-atomics/LICENSE.txt "$stage/Swift-Atomics-LICENSE.txt"
BR_MINI_HOST="${1:-100.80.130.61}" zsh "$stage/restore-air-relay.sh"
