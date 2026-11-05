#!/bin/zsh
# Compiles the production mark code into a disposable app, tests it through
# AppKit, and writes a contact sheet. Does not launch or register BRIGHTMESS.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-.build/brand-proof.png}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/BrandProof.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -parse-as-library Sources/BrightnessRelay/DeskMark.swift scripts/check-brand-icons.swift -o "$app/Contents/MacOS/BrandProof"
cp Assets/Brand/Compiled/{Assets.car,BRIGHTMESS.icns} "$app/Contents/Resources/"
info="$app/Contents/Info.plist"
plutil -create xml1 "$info"
plutil -insert CFBundlePackageType -string APPL "$info"
plutil -insert CFBundleIdentifier -string dev.pranav.Brightmess.IconProof "$info"
plutil -insert CFBundleExecutable -string BrandProof "$info"
plutil -insert CFBundleIconFile -string BRIGHTMESS "$info"
plutil -insert CFBundleIconName -string BRIGHTMESS "$info"
"$app/Contents/MacOS/BrandProof" "$out" "${2:-$app}"
