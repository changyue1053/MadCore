#!/usr/bin/env bash
# Exercise the pinned compiler's ABI tooling, not a checked-in baseline.
set -euo pipefail
root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
scratch="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-jvm-abi.XXXXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -C "$root" archive HEAD | tar -xf - -C "$scratch"
cd "$scratch"

# The updater accepts references only below the workspace root. Keep generated
# candidate references and the source mutation strictly in this disposable copy.
test ! -e api-baseline/jvm
python3 tools/test_abi_candidate_inventory.py
gradle=(./gradlew --no-daemon --console=plain -Pmadcore.target=jvm -Pmadcore.abiProbe=true)
"${gradle[@]}" dumpLegacyAbi
python3 tools/check_abi_candidate_inventory.py jvm actual
test ! -e core-testkit/build/api-baseline/jvm
"${gradle[@]}" updateLegacyAbi
python3 tools/check_abi_candidate_inventory.py jvm reference
"${gradle[@]}" checkLegacyAbi

drift=core-config/src/commonMain/kotlin/MadCoreAbiProbeDrift.kt
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
actual=core-config/build/api-baseline/jvm/core-config.api
grep -Fq 'madCoreAbiProbeDrift' "$actual"
rm -- "$drift"
"${gradle[@]}" :core-config:checkLegacyAbi
if grep -Fq 'madCoreAbiProbeDrift' "$actual"; then
    echo 'ABI dump still contains the removed drift control' >&2
    exit 1
fi
python3 tools/check_abi_candidate_inventory.py jvm actual
echo 'JVM ABI candidate passed: complete inventories, drift rejected, clean ABI restored'
