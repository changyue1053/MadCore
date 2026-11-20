#!/usr/bin/env bash
# Diagnostic only. Not a comparison, runtime test, or system SDK installer.
set -euo pipefail
stage=setup
work=
passed=false
exec 3>&1
cleanup() {
    if [[ -n "$work" ]]; then rm -rf -- "$work"; fi
    if [[ "$passed" == false ]]; then
        printf 'ABI ios baseline probe: incomplete (%s)\n' "$stage" >&3
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ $# == 0 ]]
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-ios-abi-probe.XXXXXXXX")
exec >"$work/private.log" 2>&1
export GRADLE_USER_HOME="$work/gradle" KONAN_DATA_DIR="$work/konan"
export DEVELOPER_DIR=/Applications/Xcode_26.0.1.app/Contents/Developer
revision=9555b58b3af91165e4a1a2a8db02ba3c1903c24a

stage=xcode-and-sdks
test "$(uname -m)" = arm64
test "$(xcodebuild -version)" = $'Xcode 26.0.1\nBuild version 17A400'
for sdk in iphoneos iphonesimulator; do
    test -d "$(xcrun --sdk "$sdk" --show-sdk-path)"
    test -n "$(xcrun --sdk "$sdk" --show-sdk-build-version)"
done

stage=archive
mkdir "$work/source"
git -C "$root" archive "$revision" | tar -xf - -C "$work/source"
cd "$work/source"
stage=wrapper-files
test -x ./gradlew
test -s gradle/wrapper/gradle-wrapper.jar
test -s gradle/wrapper/gradle-wrapper.properties

stage=jdk21
"${JAVA_HOME:?JDK 21 required}/bin/java" -version >"$work/jdk.log" 2>&1
grep -Eq 'version "21([."]|$)' "$work/jdk.log"

# Never interpolate process output into the report. Classify only recognized
# failure shapes. Unknown task/configuration/compiler errors keep stage name.
classify() {
    local log=$1
    if grep -Eiq 'java\.(net|io)\..*(UnknownHostException|ConnectException|SocketTimeoutException)|SSLHandshakeException|HTTP response code: (401|403|404|429|5[0-9]{2})' "$log"; then
        printf '%s-transport\n' "$stage"
    elif grep -Eiq 'Could not resolve.*abi-tools|[[:space:]]Could not find org\.jetbrains\.kotlin:abi-tools' "$log"; then
        printf '%s-abi-tools-resolution\n' "$stage"
    elif grep -Eiq '(cannot|could not) (locate|find) task.*dumpLegacyAbi|task .*dumpLegacyAbi.*not found' "$log"; then
        printf '%s-task-missing\n' "$stage"
    elif grep -Eiq '^> Task :core-config:compileKotlinIos(Arm64|SimulatorArm64) FAILED' "$log"; then
        printf '%s-native-task\n' "$stage"
    elif grep -Eiq '^> Task :core-config:dumpLegacyAbi FAILED' "$log"; then
        printf '%s-render-task\n' "$stage"
    elif grep -Eiq '(could not resolve|could not find all artifacts for|could not resolve all dependencies)' "$log"; then
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
stage=wrapper-bootstrap
run_gradle --version
grep -Fxq 'Gradle 9.4.1' "$work/wrapper-bootstrap.log"

gradle=(-Pmadcore.target=ios -Pmadcore.abiProbe=true :core-config:dumpLegacyAbi)
stage=gradle-task-plan
run_gradle "${gradle[@]}" --dry-run
grep -Eq '^:core-config:compileKotlinIosArm64([[:space:]]|$)' "$work/gradle-task-plan.log"
grep -Eq '^:core-config:compileKotlinIosSimulatorArm64([[:space:]]|$)' "$work/gradle-task-plan.log"

stage=compile-and-dump
run_gradle "${gradle[@]}"
stage=dump-inventory
actual=core-config/build/api-baseline/ios
test -s "$actual/core-config.api"
test "$(sed -n '1p' "$actual/core-config.klib.api")" = '// Klib ABI Dump'
test "$(sed -n '2p' "$actual/core-config.klib.api")" = '// Targets: [iosArm64, iosSimulatorArm64]'
passed=true
printf 'ABI ios baseline probe: core-config JVM + both compiled KLIB targets present; no cross-version result\n' >&3
