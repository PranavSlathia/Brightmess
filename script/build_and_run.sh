#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-run}"
case "$MODE" in run|--prepare|--verify) ;; *) echo 'usage: build_and_run.sh [run|--prepare|--verify]' >&2; exit 2;; esac
# Only our separate fixture executable; never the installed brightness-relay.
if pgrep -x BRMFixture >/dev/null; then pkill -TERM -x BRMFixture; fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_27.2.app/Contents/Developer}"
scripts/swiftpm.sh build --scratch-path .build-arrange
APP="$ROOT/dist/BRIGHTMESS Arrange Fixture.app"
mkdir -p "$APP/Contents/MacOS"
install -m 755 .build-arrange/debug/brightness-relay "$APP/Contents/MacOS/BRMFixture"
install -m 644 Tests/Fixtures/ArrangeAppInfo.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
if [[ "$MODE" != --prepare ]]; then /usr/bin/open -n "$APP"; fi
if [[ "$MODE" == --verify ]]; then
  for _ in {1..10}; do if pgrep -x BRMFixture >/dev/null; then exit 0; fi; sleep 0.2; done
  exit 1
fi
