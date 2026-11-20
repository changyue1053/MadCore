#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Wpedantic -g -O1 -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  "$here/mc_copied_http_test.c" -o "$work/test"
options=detect_leaks=1:halt_on_error=1
if [[ "$(uname -s)" == Darwin ]]; then
  options=detect_leaks=0:halt_on_error=1
  echo 'macOS ASan does not support LeakSanitizer; address/undefined checks remain enabled'
fi
ASAN_OPTIONS="${ASAN_OPTIONS:-$options}" \
  UBSAN_OPTIONS=halt_on_error=1 "$work/test"
