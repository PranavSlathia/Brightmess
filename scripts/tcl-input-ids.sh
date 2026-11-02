#!/bin/zsh
# Read-only, opt-in troubleshooting on a TV you have already authorized.
set -euo pipefail
if (( $# != 1 )); then print -u2 'Usage: zsh scripts/tcl-input-ids.sh <authorized-TV-IP:port>'; exit 2; fi
serial="$1"
export LC_ALL=C
command -v adb >/dev/null || { print -u2 'Install Android platform-tools on the Mini first.'; exit 1; }
[[ "$serial" != -* && "$serial" == *:* && "$(adb -s "$serial" get-state 2>/dev/null)" == device ]] || {
  print -u2 'Select the TV on its own network/debugging screen and authorize it first.'; exit 1; }
maker="$(adb -s "$serial" shell getprop ro.product.manufacturer | tr -d '\r')"
[[ "${maker:l}" == *tcl* || "${maker:l}" == *iffalcon* ]] || {
  print -u2 "Expected TCL/iFFALCON; stopped before reading inputs."; exit 1; }
print 'Candidate input IDs (not confirmed port mappings):'
adb -s "$serial" shell dumpsys tv_input | rg -o '[[:alnum:]_.]+/[[:alnum:]_.$]+/HW[0-9]+' | sort -u
print 'Current TCL input property, if available:'
adb -s "$serial" shell getprop sys.tcl.inputid
print 'Compare on-screen ports. Disable debugging on the TV before testing the paired input links.'
