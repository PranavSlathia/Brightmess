#!/bin/zsh
set -euo pipefail
# The CLT 6.4 SwiftBuild plugin registry fails before compiling. Its native
# engine builds this package successfully; no system toolchain files are edited.
operation="$1"
shift
case "$operation" in
  build|test|run)
    exec /usr/bin/swift "$operation" --build-system native "$@"
    ;;
  *)
    exec /usr/bin/swift "$operation" "$@"
    ;;
esac
