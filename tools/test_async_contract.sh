#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Explicitly undo NDEBUG: these are executable test assertions, never SDK gates.
cc -std=c11 -Wall -Wextra -Werror -pedantic -UNDEBUG -fsanitize=address,undefined -fno-omit-frame-pointer \
  "$root/harmony/experimental/async-contract/operation_registry_test.c" -o "$work/test"
"$work/test"
