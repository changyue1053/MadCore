#!/usr/bin/env bash
# Experimental opt-in only. Uses the already provisioned pinned CPF dependencies.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deps=${KONAN_DATA_DIR:-$HOME/.konan}/dependencies
case "$(uname -s):$(uname -m)" in
  Darwin:arm64) llvm="$deps/cpf-llvm-19-aarch64-macos-dev-20" ;;
  Linux:x86_64) llvm="$deps/cpf-llvm-19-x86_64-linux-dev-20" ;;
  *) echo 'Unsupported build host for pinned experimental C registry' >&2; exit 1 ;;
esac
sysroot="$deps/sysroot-ohos-aarch64-6.0.2.640-04"
out="$root/core-net/build/copied-http"
mkdir -p "$out"
"$llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$sysroot" -std=c11 -fPIC -Wall -Wextra -Werror -pthread \
  -I"$root/harmony/experimental/copied-http" -c "$root/harmony/experimental/copied-http/copied_http.c" -o "$out/copied_http.o"
"$llvm/bin/llvm-ar" rcs "$out/libmadcore_copied_http.a" "$out/copied_http.o"
