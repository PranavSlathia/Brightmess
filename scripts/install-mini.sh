#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/BRIGHTMESS.app"
LEGACY="$HOME/Applications/Brightness Relay.app"
OLD="$APP"
[[ ! -d "$LEGACY" ]] || OLD="$LEGACY"
if [[ -d "$LEGACY" && -d "$APP" ]]; then print -u2 'Both app names exist; refusing to overwrite either.'; exit 1; fi
if [[ -d "$OLD" ]]; then
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "$OLD/Contents/Info.plist")" == dev.pranav.BrightnessRelay ]] || exit 1
fi
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.receiver.plist"
TOKEN="$HOME/.config/brightness-relay/token"
SUPPORT="$HOME/Library/Application Support/Brightness Relay/Backups"
STAGE_ONLY=0
if (( $# )); then
  [[ $# == 1 && "$1" == --stage-only ]] || { print -u2 'usage: install-mini.sh [--stage-only]'; exit 2; }
  STAGE_ONLY=1
fi
cd "$ROOT"
if [[ "${BR_SKIP_BUILD:-0}" != 1 ]]; then
  "$ROOT/scripts/swiftpm.sh" build -c release
fi
if (( STAGE_ONLY )); then
  STAGE="$(mktemp -d "$ROOT/.build/mini-preview.XXXXXX")"
else
  mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  STAGE="$(mktemp -d "$HOME/Applications/.brightness-update.XXXXXX")"
fi
STAGED_APP="$STAGE/BRIGHTMESS.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 755 .build/release/brightness-relay "$STAGED_APP/Contents/MacOS/brightness-relay"
for asset in BRIGHTMESS.icns Assets.car; do
  install -m 644 "Assets/Brand/Compiled/$asset" "$STAGED_APP/Contents/Resources/$asset"
done
install -m 644 NOTICE "$STAGED_APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
install -m 644 .build/checkouts/SunKit/LICENSE "$STAGED_APP/Contents/Resources/SunKit-LICENSE.txt"
install -m 644 .build/checkouts/swift-atomics/LICENSE.txt "$STAGED_APP/Contents/Resources/Swift-Atomics-LICENSE.txt"
INFO="$STAGED_APP/Contents/Info.plist"
plutil -create xml1 "$INFO"
plutil -insert CFBundleExecutable -string brightness-relay "$INFO"
plutil -insert CFBundleIdentifier -string dev.pranav.BrightnessRelay "$INFO"
plutil -insert CFBundleName -string "BRIGHTMESS" "$INFO"
plutil -insert CFBundleDisplayName -string "BRIGHTMESS" "$INFO"
plutil -insert CFBundlePackageType -string APPL "$INFO"
plutil -insert CFBundleIconFile -string BRIGHTMESS "$INFO"
plutil -insert CFBundleIconName -string BRIGHTMESS "$INFO"
VERSION=0.12.3
BUILD=26
plutil -insert CFBundleShortVersionString -string "$VERSION" "$INFO"
plutil -insert CFBundleVersion -string "$BUILD" "$INFO"
plutil -insert NSLocalNetworkUsageDescription -string "Find your selected Android TV and send input commands on your local network." "$INFO"
plutil -insert NSBonjourServices -json '["_androidtvremote2._tcp"]' "$INFO"
plutil -insert LSMinimumSystemVersion -string 14.0 "$INFO"
plutil -insert LSUIElement -bool true "$INFO"
plutil -insert NSHighResolutionCapable -bool true "$INFO"
# Keep a stable identity across updates. Never auto-pick from find-identity:
# its list can include a revoked certificate. Never silently fall back to ad hoc.
SIGNING_IDENTITY="${BR_SIGNING_IDENTITY:-}"
SIGNING_CONFIG="$HOME/.config/brightness-relay/signing-identity"
if [[ -z "$SIGNING_IDENTITY" && -f "$SIGNING_CONFIG" ]]; then
  IFS= read -r SIGNING_IDENTITY < "$SIGNING_CONFIG"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 'Set BR_SIGNING_IDENTITY to a verified certificate fingerprint, or save it in ~/.config/brightness-relay/signing-identity. Installed app not changed.'
  exit 1
fi
if [[ "$SIGNING_IDENTITY" == - ]]; then
  (( STAGE_ONLY )) || { print -u2 'Ad-hoc signing is only allowed with --stage-only; it breaks identity continuity on updates.'; exit 1; }
else
  /usr/bin/swift "$ROOT/scripts/verify-signing-identity.swift" "$SIGNING_IDENTITY"
fi
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
if [[ -d "$OLD" && "$SIGNING_IDENTITY" != - ]]; then
  OLD_SIGNATURE="$(codesign -dv "$OLD" 2>&1)" || { print -u2 'Cannot inspect installed signature; update stopped.'; exit 1; }
  # Do not pipe codesign into grep -q under pipefail: its early exit can cause
  # SIGPIPE and misclassify an ad-hoc predecessor as a certificate-signed app.
  if [[ "$OLD_SIGNATURE" != *'Signature=adhoc'* ]]; then
    OLD_REQUIREMENT="$(codesign -d -r- "$OLD" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$OLD_REQUIREMENT" ]] || { print -u2 'Cannot establish installed signing identity; update stopped.'; exit 1; }
    codesign --verify --strict -R "=$OLD_REQUIREMENT" "$STAGED_APP" || {
      print -u2 'New app does not match the installed signing identity. Installed app was not changed.'; exit 1;
    }
  fi
fi
if (( STAGE_ONLY )); then
  print "$STAGED_APP"
  exit 0
fi
mkdir -p "$SUPPORT"
BACKUP="$(mktemp -d "$SUPPORT/$(date +%Y%m%d-%H%M%S).XXXXXX")"
[[ ! -f "$HOME/.local/bin/brightness-relay" ]] || cp -p "$HOME/.local/bin/brightness-relay" "$BACKUP/cli"
[[ -f "$TOKEN" ]] || .build/release/brightness-relay token create

mkdir -p "$BACKUP"
install -m 755 "$ROOT/scripts/rollback-mini.sh" "$BACKUP/Rollback Mini.command"
[[ ! -f "$PLIST" ]] || cp -p "$PLIST" "$BACKUP/receiver.plist"
if [[ -f "$PLIST" ]]; then
  cp -p "$PLIST" "$STAGE/receiver.plist"
  found=0
  for i in {0..64}; do
    arg="$(plutil -extract "ProgramArguments.$i" raw -o - "$PLIST" 2>/dev/null)" || break
    if [[ "$arg" == "$LEGACY" || "$arg" == "$APP" ]]; then
      /usr/libexec/PlistBuddy -c "Set :ProgramArguments:$i $APP" "$STAGE/receiver.plist"
      # Verify the entire argument list, not just the value at i. Some CLTs
      # insert rather than replace array elements through plutil -replace.
      /usr/bin/perl -MJSON::PP -e '
        my ($old,$new,$i,$path)=@ARGV;
        sub args { open my $fh,"-|","/usr/bin/plutil","-extract","ProgramArguments","json","-o","-",shift or die; local $/; return decode_json(<$fh>); }
        my $a=args($old); $a->[$i]=$path; my $b=args($new);
        die "Unexpected receiver argument change\n" unless encode_json($a) eq encode_json($b);
      ' "$PLIST" "$STAGE/receiver.plist" "$i" "$APP"
      found=1; break
    fi
  done
  (( found )) || { print -u2 'Unrecognized receiver arguments; installed app not touched.'; exit 1; }
fi
launchctl bootout "gui/$(id -u)/dev.pranav.brightness-relay.receiver" >/dev/null 2>&1 || true
pkill -TERM -f "^$OLD/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1 || true
for attempt in {1..30}; do
  pgrep -f "^$OLD/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1 || break
  sleep 0.1
done
if pgrep -f "^$OLD/Contents/MacOS/brightness-relay menu" >/dev/null 2>&1; then
  echo "Existing app did not exit; update stopped before replacing it." >&2
  exit 1
fi
[[ ! -d "$OLD" ]] || mv "$OLD" "$BACKUP/${OLD:t}"
restore_on_failure() {
  if [[ -f "$BACKUP/receiver.plist" && -d "$BACKUP/${OLD:t}" ]]; then
    zsh "$BACKUP/Rollback Mini.command" || print -u2 "Recovery required: $BACKUP"
  fi
}
trap 'restore_on_failure' ZERR
mv "$STAGED_APP" "$APP"
install -m 755 .build/release/brightness-relay "$HOME/.local/bin/brightness-relay"
[[ ! -f "$STAGE/receiver.plist" ]] || mv "$STAGE/receiver.plist" "$PLIST"
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
        plutil -extract controls.uiBuild raw -o - - 2>/dev/null | grep -qx "$BUILD"; then
      print "BRIGHTMESS receiver build $BUILD verified."
      break
    fi
    sleep 2
  done
fi
if ! "$HOME/.local/bin/brightness-relay" status --host 127.0.0.1 2>/dev/null |
     plutil -extract controls.uiBuild raw -o - - 2>/dev/null | grep -qx "$BUILD"; then
  restore_on_failure
  print -u2 "Receiver did not start; see $BACKUP"; exit 1
fi
trap - ZERR
echo "BRIGHTMESS $VERSION installed. Previous app and launch settings: $BACKUP"
