#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
compiler="${CC:-cc}"
# Required sanitizers: fail closed if unavailable, rather than silently skipping them.
"$compiler" -std=c11 -Wall -Wextra -Werror -g -O1 \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$root/tools/native_bridge_test" \
  "$root/tools/native_bridge_test/bridge_test.c" -o "$work/bridge-test"
ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}" UBSAN_OPTIONS=halt_on_error=1 "$work/bridge-test"
