#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MINI_HOST="${BR_MINI_HOST:-100.80.130.61}"
SUPPORT="$HOME/Library/Application Support/Brightness Relay"
BIN="$SUPPORT/brightness-relay"
TOKEN="$HOME/.config/brightness-relay/token"
PLIST="$HOME/Library/LaunchAgents/dev.pranav.brightness-relay.source.plist"
LABEL="dev.pranav.brightness-relay.source"
LOG="$HOME/Library/Logs/BrightnessRelay-source.log"

fail() {
  print -u2 -- "REPAIR FAILED: $1"
  exit 1
}

[[ -f "$ROOT/brightness-relay" ]] || fail "Keep this installer beside the supplied brightness-relay file."
[[ -f "$ROOT/token" ]] || fail "The pairing file is missing from this repair bundle."
/usr/bin/codesign --verify "$ROOT/brightness-relay" ||
  fail "The supplied relay executable failed its signature check."

print -- "Checking this MacBook's built-in brightness..."
sample="$("$ROOT/brightness-relay" sample)" ||
  fail "Run this repair on the MacBook Air with its lid open."

/bin/mkdir -p "$SUPPORT" "$(dirname "$TOKEN")" "$(dirname "$PLIST")" "$(dirname "$LOG")"
/bin/chmod 700 "$SUPPORT"
[[ ! -f "$PLIST" ]] ||
  /bin/cp -p "$PLIST" "$PLIST.before-restore-$(date +%Y%m%d-%H%M%S)"

# Test the existing pairing first; never replace an existing token silently.
if [[ ! -f "$TOKEN" ]]; then
  /usr/bin/install -m 600 "$ROOT/token" "$TOKEN"
fi
preflight="$("$ROOT/brightness-relay" status --host "$MINI_HOST" --token-file "$TOKEN")" || fail "Mini authentication failed; service unchanged."
version=$(print -r -- "$preflight" | plutil -extract version raw -o - -)
[[ "$version" == 0.8.0 ]] || fail "Install Mini 0.8 first; service unchanged."
oldSession=$(print -r -- "$preflight" | plutil -extract sourceSession raw -o - - 2>/dev/null || true)
mkdir -p "$SUPPORT/Backups"
BACKUP=$(mktemp -d "$SUPPORT/Backups/Air-$(date +%Y%m%d-%H%M%S).XXXXXX")
touch "$BACKUP/air-backup"
[[ ! -f "$PLIST" ]] || cp -p "$PLIST" "$BACKUP/source.plist"
[[ ! -f "$BIN" ]] || cp -p "$BIN" "$BACKUP/helper"
install -m 755 "$ROOT/rollback-air.sh" "$BACKUP/Rollback Air.command"
cutover=1
STAGED_PLIST=''
cleanup() {
  local rc=$?
  trap - EXIT
  [[ -z "$STAGED_PLIST" ]] || /bin/rm -f "$STAGED_PLIST"
  if (( rc != 0 && cutover )); then zsh "$BACKUP/Rollback Air.command"; fi
  exit "$rc"
}
trap cleanup EXIT
/bin/launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
/usr/bin/install -m 755 "$ROOT/brightness-relay" "$BIN"
/usr/bin/install -m 644 "$ROOT/THIRD-PARTY-NOTICES.txt" "$SUPPORT/THIRD-PARTY-NOTICES.txt"
/usr/bin/install -m 644 "$ROOT/SunKit-LICENSE.txt" "$SUPPORT/SunKit-LICENSE.txt"
/usr/bin/install -m 644 "$ROOT/Swift-Atomics-LICENSE.txt" "$SUPPORT/Swift-Atomics-LICENSE.txt"

STAGED_PLIST="$(/usr/bin/mktemp "$(dirname "$PLIST")/.brightness-source.XXXXXX")"
/usr/bin/plutil -create xml1 "$STAGED_PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments -array "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$BIN" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string source "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.2 -string --host "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.3 -string "$MINI_HOST" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.4 -string --token-file "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.5 -string "$TOKEN" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.6 -string --sync-mode "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.7 -string live "$STAGED_PLIST"
/usr/bin/plutil -insert RunAtLoad -bool true "$STAGED_PLIST"
/usr/bin/plutil -insert KeepAlive -bool true "$STAGED_PLIST"
/usr/bin/plutil -insert ThrottleInterval -integer 10 "$STAGED_PLIST"
/usr/bin/plutil -insert StandardOutPath -string "$LOG" "$STAGED_PLIST"
/usr/bin/plutil -insert StandardErrorPath -string "$LOG" "$STAGED_PLIST"
# Make successful sends visible when launchd redirects stdout to a file.
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$STAGED_PLIST"
/usr/bin/plutil -insert EnvironmentVariables.NSUNBUFFEREDIO -string YES "$STAGED_PLIST"
/usr/bin/plutil -lint "$STAGED_PLIST" >/dev/null
/bin/chmod 644 "$STAGED_PLIST"
/bin/mv "$STAGED_PLIST" "$PLIST"
/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST" ||
  fail "The test reading succeeded, but the login service could not start."

for attempt in {1..45}; do
  /bin/sleep 2
  result=$("$BIN" status --host "$MINI_HOST" --token-file "$TOKEN" 2>/dev/null) || continue
  current=$(print -r -- "$result" | plutil -extract sourceSession raw -o - - 2>/dev/null || true)
  mode=$(print -r -- "$result" | plutil -extract sourceMode raw -o - - 2>/dev/null || true)
  state=$(print -r -- "$result" | plutil -extract sourceState raw -o - - 2>/dev/null || true)
  if [[ -n "$current" && "$oldSession" != "$current" && "$mode" == live && "$state" == Live ]] &&
      launchctl print "gui/$(id -u)/$LABEL" | /usr/bin/grep 'pid =' >/dev/null; then
    cutover=0
    print "LIVE UPDATE SUCCEEDED: the Mini accepted a reading from the new Air session $current."
    print "Backup and standalone rollback: $BACKUP"
    print "For the quiet CPU check: zsh \"$ROOT/measure-relay.sh\" air"
    exit 0
  fi
done
fail 'No fresh live Air session confirmed on the Mini. Restoring the previous helper.'
