#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MINI_HOST="100.80.130.61"
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
percentage="$(/usr/bin/awk -v value="$sample" 'BEGIN { printf "%.2f", value * 100 }')"

/bin/mkdir -p "$SUPPORT" "$(dirname "$TOKEN")" "$(dirname "$PLIST")" "$(dirname "$LOG")"
/bin/chmod 700 "$SUPPORT"
[[ ! -f "$PLIST" ]] ||
  /bin/cp -p "$PLIST" "$PLIST.before-restore-$(date +%Y%m%d-%H%M%S)"

# Test the existing pairing first; never replace an existing token silently.
if [[ ! -f "$TOKEN" ]]; then
  /usr/bin/install -m 600 "$ROOT/token" "$TOKEN"
fi
print -- "Sending current brightness and ambient colour to the Mac mini..."
"$ROOT/brightness-relay" send-sample --host "$MINI_HOST" --token-file "$TOKEN" ||
  fail "The Mini did not accept the test reading. The background service has not been changed."

/bin/launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
/usr/bin/install -m 755 "$ROOT/brightness-relay" "$BIN"
/usr/bin/install -m 644 "$ROOT/THIRD-PARTY-NOTICES.txt" "$SUPPORT/THIRD-PARTY-NOTICES.txt"
/usr/bin/install -m 644 "$ROOT/SunKit-LICENSE.txt" "$SUPPORT/SunKit-LICENSE.txt"
/usr/bin/install -m 644 "$ROOT/Swift-Atomics-LICENSE.txt" "$SUPPORT/Swift-Atomics-LICENSE.txt"

STAGED_PLIST="$(/usr/bin/mktemp "$(dirname "$PLIST")/.brightness-source.XXXXXX")"
trap '/bin/rm -f "$STAGED_PLIST"' EXIT
/usr/bin/plutil -create xml1 "$STAGED_PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments -array "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$BIN" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string source "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.2 -string --host "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.3 -string "$MINI_HOST" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.4 -string --token-file "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.5 -string "$TOKEN" "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.6 -string --interval "$STAGED_PLIST"
/usr/bin/plutil -insert ProgramArguments.7 -string 1800 "$STAGED_PLIST"
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

/bin/sleep 2
if ! /bin/launchctl print "gui/$(id -u)/$LABEL" | /usr/bin/grep 'pid =' >/dev/null; then
  /bin/launchctl print "gui/$(id -u)/$LABEL" | /usr/bin/grep -E 'state =|last exit code|program ='
  fail "The login service did not stay running. Share the output above."
fi
print -- "UPDATE SUCCEEDED: a fresh reading was accepted, and the background relay is running."
print -- "Automatic sync remains every 30 minutes, with Sync Now available."
print -- "Choose Adaptive under White balance in the Mini app to use valid colour readings."
print -- "You can delete the downloaded repair folder and ZIP after verification."
