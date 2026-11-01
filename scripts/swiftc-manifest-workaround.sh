#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/swiftc -I "$ROOT/.build/fixed-manifest-api" "$@"
