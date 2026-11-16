#!/bin/zsh
set -eu
case "${1:-air}" in
  air) pid=$(launchctl print "gui/$(id -u)/dev.pranav.brightness-relay.source" | awk '/^[[:space:]]*pid =/{print $3; exit}') ;;
  mini) pid=$(pgrep -f "^$HOME/Applications/(BRIGHTMESS|Brightness Relay).app/Contents/MacOS/brightness-relay menu" | head -1) ;;
  *) print -u2 'Usage: measure-relay.sh air|mini'; exit 2 ;;
esac
[[ -n "$pid" ]] || { print -u2 'No running helper'; exit 1; }
exec /usr/bin/swift "${0:A:h}/measure-performance.swift" "${1:-air}" "$pid"
