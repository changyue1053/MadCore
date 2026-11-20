#!/usr/bin/env bash
# One-transition collection; never upload, print, or retain raw differences.
set -euo pipefail
lane=${1:-}
case "$lane" in jvm|android|ios) ;; *) exit 2 ;; esac
base=f8b864718a35d95a1e87331d216b995c3ac0c55d
source_sha=9555b58b3af91165e4a1a2a8db02ba3c1903c24a
stage=setup
work=
reported=false
exec 3>&1
report() {
    printf '%s\n' "$1" >&3
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
}
cleanup() {
    if [[ -n "$work" ]]; then rm -rf -- "$work"; fi
    if [[ "$reported" == false ]]; then
        report "ABI $lane: identical=0, changed=0, noncomparable=0, incomplete=1 ($stage)"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-abi-compare.XXXXXXXX")
exec >"$work/run.log" 2>&1
# Keep Gradle and Kotlin/Native dependency caches out of the machine SDK paths.
export GRADLE_USER_HOME="$work/gradle" KONAN_DATA_DIR="$work/konan"

stage=exact-transition
test "$(git -C "$root" rev-parse HEAD^)" = "$base"
test "$(git -C "$root" rev-parse HEAD^^)" = "$source_sha"
test "$(git -C "$root" diff --name-only "$base" HEAD)" = \
    $'.github/workflows/phase3-official-abi.yml\ntools/compare_official_abi.py\ntools/run_official_abi_comparison.sh'
stage=abi-prerequisites
gradle_flags=()
if [[ "$lane" == ios ]]; then
    test "$(uname -m)" = arm64
    test "$DEVELOPER_DIR" = /Applications/Xcode_26.0.1.app/Contents/Developer
    test "$(xcodebuild -version)" = $'Xcode 26.0.1\nBuild version 17A400'
    for sdk in iphoneos iphonesimulator; do
        xcrun --sdk "$sdk" --show-sdk-build-version
    done
elif [[ "$lane" == android ]]; then
    sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    test -n "$sdk"
    test -s "$sdk/platforms/android-36/android.jar"
    gradle_flags+=(-Pandroid.builder.sdkDownload=false)
fi

for side in baseline overlay; do
    stage="$side-archive"
    mkdir "$work/$side"
    git -C "$root" archive "$source_sha" | tar -xf - -C "$work/$side"
    stage="$side-compile"
    (
        cd "$work/$side"
        task=dumpLegacyAbi
        if [[ "$side" == overlay ]]; then
            python3 .github/phase3/apply-official-toolchain.py
            task=internalDumpKotlinAbi
        fi
        ./gradlew --no-daemon --console=plain "${gradle_flags[@]}" \
            "-Pmadcore.target=$lane" -Pmadcore.abiProbe=true "$task"
    )
done

stage=abi-inventory-or-report
status=0
summary=$(python3 -B "$root/tools/compare_official_abi.py" "$lane" \
    "$work/baseline" "$work/overlay" --private-report "$work/diff.txt") || status=$?
if [[ "$summary" =~ ^ABI\ (jvm|android|ios):\ identical=[0-9]+,\ changed=[0-9]+,\ noncomparable=[0-9]+,\ incomplete=[0-9]+$ ]]; then
    report "$summary"
    reported=true
else
    exit 1
fi
# Deltas/scope/format are advisory; missing inventory or compilation fails.
exit "$status"
