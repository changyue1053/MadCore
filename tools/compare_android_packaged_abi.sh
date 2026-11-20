#!/usr/bin/env bash
# Both arguments are caller-supplied producer trees with assembled Release AARs.
# Outputs are temporary; content and paths are never printed.
set -euo pipefail
umask 077
[[ $# == 2 ]] || { echo 'Usage: compare_android_packaged_abi.sh BASELINE_TREE CANDIDATE_TREE' >&2; exit 2; }
root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-aar-abi.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
status() { printf '%s\n' "MADCORE_ANDROID_PACKAGED_ABI_STAGE=$1 RESULT=$2"; }
if ! prepared=$(python3 -B "$root/tools/compare_android_packaged_abi.py" prepare \
     "$1" "$2" "$work/input" 2>"$work/preflight.log"); then
    status input failed
    exit 1
fi
if [[ ! "$prepared" =~ ^PACKAGED_ANDROID_AAR_INPUTS=9\ BASELINE_CLASSES=[1-9][0-9]*\ CANDIDATE_CLASSES=[1-9][0-9]*$ ]]; then
    status input failed
    exit 1
fi
printf '%s\n' "$prepared"
export GRADLE_USER_HOME="$work/gradle-home" \
       MADCORE_AAR_ABI_INPUT="$work/input" MADCORE_AAR_ABI_OUTPUT="$work/output"
mkdir -- "$GRADLE_USER_HOME"
printf '%s\n' 'org.gradle.java.installations.auto-download=false' > "$GRADLE_USER_HOME/gradle.properties"
cp -R -- "$root/tools/android-packaged-abi-analyzer" "$work/analyzer"
if ! "$root/gradlew" --no-daemon --console=plain -p "$work/analyzer" run >"$work/analyzer.log" 2>&1; then
    status analyzer failed
    exit 1
fi
code=0
comparison=$(python3 -B "$root/tools/compare_android_packaged_abi.py" compare \
    "$work/output" 2>"$work/comparison.log") || code=$?
if [[ "$comparison" =~ ^PACKAGED_ANDROID_AAR_ABI_EQUAL=[0-9]+\ CHANGED=[0-9]+$ ]]; then
    printf '%s\n' "$comparison"
fi
if [[ "$code" == 0 && "$comparison" == 'PACKAGED_ANDROID_AAR_ABI_EQUAL=9 CHANGED=0' ]]; then
    status comparison passed
else
    status comparison failed
    exit 1
fi
