#!/bin/zsh
# Maintainer tool: end-user installs use the checked-in compiler outputs.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
xcrun actool Assets/Brand/BRIGHTMESS.icon --compile "$tmp" --app-icon BRIGHTMESS \
  --platform macosx --minimum-deployment-target 14.0 --target-device mac \
  --output-partial-info-plist "$tmp/icon.plist" --output-format human-readable-text
for key in CFBundleIconFile CFBundleIconName; do
  [[ "$(plutil -extract "$key" raw -o - "$tmp/icon.plist")" == BRIGHTMESS ]]
done
for name in Assets.car BRIGHTMESS.icns; do
  [[ -s "$tmp/$name" ]]
  install -m 644 "$tmp/$name" "Assets/Brand/Compiled/$name"
done
