#!/usr/bin/env bash
# Experimental facade; all persistent state lives in the one libmadcore registry.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deps=${KONAN_DATA_DIR:-$HOME/.konan}/dependencies
case "$(uname -s):$(uname -m)" in
 Darwin:arm64) llvm="$deps/cpf-llvm-19-aarch64-macos-dev-20" ;;
 Linux:x86_64) llvm="$deps/cpf-llvm-19-x86_64-linux-dev-20" ;;
 *) exit 1 ;;
esac
sysroot="$deps/sysroot-ohos-aarch64-6.0.2.640-04"
lib="$root/madcore/build/bin/ohosArm64/releaseShared"
"$llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$sysroot" -std=c11 -fPIC -shared -Wall -Wextra -Werror \
 "$root/harmony/experimental/copied-http/bridge_napi.c" -I"$root/harmony/native" -I"$root/harmony/experimental/copied-http" \
 -L"$sysroot/usr/lib/aarch64-linux-ohos" -L"$lib" -lmadcore -lace_napi.z -Wl,--no-undefined \
 -Wl,-soname,libmadcore_copied_bridge.so -o "$lib/libmadcore_copied_bridge.so"
READELF="$llvm/bin/llvm-readelf" python3 "$root/tools/check_copied_http_link.py" "$lib/libmadcore.so" "$lib/libmadcore_copied_bridge.so"
