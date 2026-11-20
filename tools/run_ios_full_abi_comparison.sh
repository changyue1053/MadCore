#!/usr/bin/env bash
# One iOS compiler-only comparison. Never emit raw build or symbol text.
set -euo pipefail
base=57adc6232dbb43605f3f2ff43287fc15772f96fc
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
        report "ABI ios: identical=0, changed=0, noncomparable=0, incomplete=1 ($stage)"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ $# == 0 ]]
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-ios-abi-full.XXXXXXXX" 2>/dev/null)
exec >"$work/private.log" 2>&1

stage=exact-transition
test "$(git -C "$root" rev-parse HEAD^)" = "$base"
test "$(git -C "$root" rev-parse HEAD~4)" = "$source_sha"
test "$(git -C "$root" diff --no-renames --name-status "$base" HEAD)" = \
    $'A\t.github/workflows/immutable-maven-android.yml\nA\t.github/workflows/phase3-ios-abi-full.yml\nA\ttools/rehearse_immutable_android_ci.sh\nA\ttools/run_ios_full_abi_comparison.sh'

# Both sides must observe the same installed Xcode and both Apple SDKs.
sdk_identity() {
    local sdk path build
    for sdk in iphoneos iphonesimulator; do
        path=$(xcrun --sdk "$sdk" --show-sdk-path) || return 1
        build=$(xcrun --sdk "$sdk" --show-sdk-build-version) || return 1
        [[ -d "$path" && -n "$build" ]] || return 1
        printf '%s\n%s\n' "$path" "$build"
    done
}
stage=xcode-and-sdks
test "$(uname -m)" = arm64
test "$DEVELOPER_DIR" = /Applications/Xcode_26.0.1.app/Contents/Developer
test "$(xcodebuild -version)" = $'Xcode 26.0.1\nBuild version 17A400'
sdk_identity >"$work/sdk-identity"
stage=jdk21
"${JAVA_HOME:?JDK 21 required}/bin/java" -version >"$work/jdk.log" 2>&1
grep -Eq 'version "21([."]|$)' "$work/jdk.log"

# Add only fixed allowlisted category suffixes to a fixed stage. Failure
# classification is evidence about error shape, not a root-cause verdict.
classify() {
    local log=$1
    if grep -Eiq 'java\.(net|io)\..*(UnknownHostException|ConnectException|SocketTimeoutException)|SSLHandshakeException|HTTP response code: (401|403|404|429|5[0-9]{2})' "$log"; then
        printf '%s-transport\n' "$stage"
    elif grep -Eiq 'Could not (resolve|find).*org\.jetbrains\.kotlin:abi-tools' "$log"; then
        printf '%s-abi-tools-resolution\n' "$stage"
    elif grep -Eiq 'Could not (resolve|find|download).*kotlin-native-prebuilt|Failed to download dependency for Kotlin Native' "$log"; then
        printf '%s-native-toolchain-resolution\n' "$stage"
    elif grep -Eiq '(cannot|could not) (locate|find) task.*(dumpLegacyAbi|internalDumpKotlinAbi)|task .*(dumpLegacyAbi|internalDumpKotlinAbi).*not found' "$log"; then
        printf '%s-task-missing\n' "$stage"
    elif grep -Eiq '^> Task :[^[:space:]]*:compileKotlinIos(Arm64|SimulatorArm64) FAILED' "$log"; then
        printf '%s-native-task\n' "$stage"
    elif grep -Eiq '^> Task :[^[:space:]]*:(dumpLegacyAbi|internalDumpKotlinAbi) FAILED' "$log"; then
        printf '%s-render-task\n' "$stage"
    elif grep -Eiq 'could not resolve|could not find all artifacts for' "$log"; then
        printf '%s-gradle-resolution\n' "$stage"
    else
        printf '%s\n' "$stage"
    fi
}
run_gradle() {
    local log="$work/$stage.log"
    if ./gradlew --no-daemon --console=plain "$@" >"$log" 2>&1; then
        return 0
    else
        stage=$(classify "$log")
        return 1
    fi
}

for side in baseline overlay; do
    stage="$side-archive"
    mkdir "$work/$side"
    git -C "$root" archive "$source_sha" | tar -xf - -C "$work/$side"
    cd "$work/$side"
    export GRADLE_USER_HOME="$work/$side-gradle" KONAN_DATA_DIR="$work/$side-konan"
    mkdir "$GRADLE_USER_HOME"
    printf '%s\n' 'org.gradle.java.installations.auto-download=false' >"$GRADLE_USER_HOME/gradle.properties"
    task=dumpLegacyAbi
    gradle_version=9.4.1
    if [[ "$side" == overlay ]]; then
        stage=overlay-apply
        python3 -B .github/phase3/apply-official-toolchain.py
        task=internalDumpKotlinAbi
        gradle_version=9.3.0
    fi
    stage="$side-wrapper-files"
    test -x ./gradlew
    test -s gradle/wrapper/gradle-wrapper.jar
    test -s gradle/wrapper/gradle-wrapper.properties

    stage="$side-sdk-identity"
    sdk_identity | cmp -s "$work/sdk-identity" -
    stage="$side-wrapper-bootstrap"
    run_gradle --version
    grep -Fxq "Gradle $gradle_version" "$work/$stage.log"

    gradle=(-Pmadcore.target=ios -Pmadcore.abiProbe=true)
    stage="$side-task-plan"
    run_gradle "${gradle[@]}" ":core-config:$task" --dry-run
    grep -Eq '^:core-config:compileKotlinIosArm64([[:space:]]|$)' "$work/$stage.log"
    grep -Eq '^:core-config:compileKotlinIosSimulatorArm64([[:space:]]|$)' "$work/$stage.log"
    stage="$side-compile-and-dump"
    run_gradle "${gradle[@]}" "$task"
    stage="$side-inventory"
    python3 -B "$root/tools/check_abi_candidate_inventory.py" ios actual --root "$work/$side"
    test ! -e core-testkit/build/api-baseline/ios
done

stage=comparison
status=0
summary=$(python3 -B "$root/tools/compare_official_abi.py" ios \
    "$work/baseline" "$work/overlay" --private-report "$work/diff.txt") || status=$?
if [[ "$summary" =~ ^ABI\ ios:\ identical=[0-9]+,\ changed=[0-9]+,\ noncomparable=[0-9]+,\ incomplete=[0-9]+$ ]]; then
    report "$summary"
    reported=true
else
    exit 1
fi
exit "$status"
