#!/bin/zsh
set -eu
case "${1:-air}" in
  air) pid=$(launchctl print "gui/$(id -u)/dev.pranav.brightness-relay.source" | awk '/^[[:space:]]*pid =/{print $3; exit}') ;;
  mini) pid=$(pgrep -f "^$HOME/Applications/(BRIGHTMESS|Brightness Relay).app/Contents/MacOS/brightness-relay menu" | head -1) ;;
  *) print -u2 'Usage: measure-relay.sh air|mini'; exit 2 ;;
esac
[[ -n "$pid" ]] || { print -u2 'No running helper'; exit 1; }
started=$(ps -p "$pid" -o lstart=)
seconds() { ps -p "$pid" -o time= | awk -F: '{s=0; for(i=1;i<=NF;i++) s=s*60+$i; print s}'; }
start=$(date +%s); initial=$(seconds)
print "Start: PID $pid, $initial CPU seconds. Leave the system in its normal quiet state."
for i in {1..20}; do
  sleep 30
  [[ "$(ps -p "$pid" -o lstart=)" == "$started" ]] || { print -u2 'Helper restarted; run discarded'; exit 1; }
done
end=$(date +%s); final=$(seconds)
awk -v elapsed="$((end-start))" -v a="$initial" -v b="$final" 'BEGIN { printf "%ds: %.3f%% of one core (%.2f CPU seconds)\n", elapsed, 100*(b-a)/elapsed, b-a }'
