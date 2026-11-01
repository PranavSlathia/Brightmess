#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BR_MINI_HOST="${1:-100.80.130.61}" exec zsh "$ROOT/Install on MacBook Air.command"
