#!/usr/bin/env bash
# Exercise the pinned compiler's ABI tooling, not a checked-in baseline.
set -euo pipefail
if [[ $# != 1 ]]; then
    echo 'Usage: bash tools/test_abi_candidate.sh jvm|android|ios' >&2
    exit 2
fi
lane=$1
case "$lane" in
  jvm) src=commonMain; actual_name=core-config.api; other_name= ;;
  android) src=androidMain; actual_name=android/core-config.api; other_name=jvm/core-config.api ;;
  ios) src=iosSimulatorArm64Main; actual_name=core-config.klib.api; other_name=core-config.api ;;
  *) echo 'Unsupported ABI probe lane' >&2; exit 2 ;;
esac
root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
scratch="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-$lane-abi.XXXXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -C "$root" archive HEAD | tar -xf - -C "$scratch"
cd "$scratch"

# The updater accepts references only below the workspace root. Keep generated
# candidate references and the source mutation strictly in this disposable copy.
test ! -e "api-baseline/$lane"
printf 'MadCore ABI candidate: %s, %s\n' "$(git -C "$root" rev-parse HEAD)" "$lane"
python3 tools/test_abi_candidate_inventory.py
gradle=(./gradlew --no-daemon --console=plain "-Pmadcore.target=$lane" -Pmadcore.abiProbe=true)
"${gradle[@]}" dumpLegacyAbi
python3 tools/check_abi_candidate_inventory.py "$lane" actual
test ! -e "core-testkit/build/api-baseline/$lane"
"${gradle[@]}" updateLegacyAbi
python3 tools/check_abi_candidate_inventory.py "$lane" reference
"${gradle[@]}" checkLegacyAbi

drift="core-config/src/$src/kotlin/MadCoreAbiProbeDrift.kt"
mkdir -p "$(dirname "$drift")"
test ! -e "$drift"
cat > "$drift" <<'KOTLIN'
package com.mad.core.config

public fun madCoreAbiProbeDrift(): Int = 42
KOTLIN
log="$scratch/abi-drift.log"
if "${gradle[@]}" :core-config:checkLegacyAbi >"$log" 2>&1; then
    cat "$log"
    echo 'ABI negative control unexpectedly passed' >&2
    exit 1
fi
cat "$log"
# Do not count failed compilation, dependency errors or a missing reference as
# successful drift detection. Match the pinned KGP comparison and own symbol.
grep -Fq 'ABI check failed for project core-config' "$log"
grep -Fq '<<<ABI has changed>>>' "$log"
grep -Fq 'madCoreAbiProbeDrift' "$log"
actual_dir="core-config/build/api-baseline/$lane"
actual="$actual_dir/$actual_name"
grep -Fq 'madCoreAbiProbeDrift' "$actual"
if [[ -n "$other_name" ]] && grep -Fq 'madCoreAbiProbeDrift' "$actual_dir/$other_name"; then
    echo 'Platform API probe unexpectedly appeared in the JVM dump' >&2
    exit 1
fi
rm -- "$drift"
"${gradle[@]}" :core-config:checkLegacyAbi
if grep -Fq 'madCoreAbiProbeDrift' "$actual"; then
    echo 'ABI dump still contains the removed drift control' >&2
    exit 1
fi
python3 tools/check_abi_candidate_inventory.py "$lane" actual
printf '%s ABI candidate passed: complete inventories, drift rejected, clean ABI restored\n' "$lane"
