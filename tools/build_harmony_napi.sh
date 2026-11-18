#!/usr/bin/env bash
# Uses the exact already-downloaded compiler/sysroot from the pinned Kotlin fork.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
deps=${KONAN_DATA_DIR:-$HOME/.konan}/dependencies
llvm="$deps/cpf-llvm-19-x86_64-linux-dev-20"
sysroot="$deps/sysroot-ohos-aarch64-6.0.2.640-04"
lib="$root/madcore/build/bin/ohosArm64/releaseShared"
test -s "$lib/libmadcore.so"
test -s "$sysroot/usr/include/napi/native_api.h"
# No fake main stub: inspect the compiler's startup-object choice before claiming loadability.
undefined=$(readelf --dyn-syms --wide "$lib/libmadcore.so" | awk '$7 == "UND" {print $8}' | sort -u)
printf '%s\n' "$undefined"
# Some ELF linkers retain an unreferenced UND table entry after discarding a section.
# A retained relocation, rather than the name alone, creates a loader requirement.
if readelf --relocs --wide "$lib/libmadcore.so" | awk '$5 ~ /^main(@|$)/ {found=1} END {exit !found}'; then
  echo 'Invalid shared library: executable startup still references main'
  exit 1
fi
readelf -h "$lib/libmadcore.so" | grep -E 'Entry point address:[[:space:]]+0x0$'
readelf -d "$lib/libmadcore.so" | grep -E 'NEEDED|SONAME'
readelf --dyn-syms --wide "$lib/libmadcore.so" | grep OH_HiDebug || true
readelf --relocs --wide "$lib/libmadcore.so" | grep OH_HiDebug || true
grep -nE 'crtFiles|linkerDynamicFlags|ohos_arm64.*=' "$HOME/.konan/kotlin-native-prebuilt-linux-x86_64-2.2.21-1.0.0/konan/konan.properties" | tail -80
"$llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$sysroot" \
  -std=c11 -fPIC -shared -Wall -Wextra -Werror \
  "$root/harmony/native/madcore_napi.c" -I"$root/harmony/native" \
  -L"$sysroot/usr/lib/aarch64-linux-ohos" -L"$lib" \
  -lmadcore -lace_napi.z -Wl,--no-undefined -Wl,-soname,libmadcore_napi.so \
  -o "$lib/libmadcore_napi.so"
readelf -h "$lib/libmadcore_napi.so" | grep AArch64
readelf -d "$lib/libmadcore_napi.so" | grep -E 'NEEDED|SONAME'
echo 'NAPI bridge linked only; runtime device load still unverified'
