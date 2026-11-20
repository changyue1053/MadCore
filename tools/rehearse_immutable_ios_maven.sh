#!/usr/bin/env bash
# Existing installed Apple tooling only. Compile/link, never install or launch.
set -euo pipefail
stage=setup
work=
passed=false
exec 3>&1
report() {
    printf '%s\n' "$1" >&3
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
}
cleanup() {
    if [[ -n "$work" ]]; then rm -rf -- "$work"; fi
    if [[ "$passed" == false ]]; then report "iOS immutable storage rehearsal incomplete ($stage)"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ $# != 1 && ( $# != 2 || "$2" != --prepare-only ) ]]; then
    echo 'Usage: bash tools/rehearse_immutable_ios_maven.sh X.Y.Z-rehearsal.N [--prepare-only]' >&2
    exit 2
fi
version=$1
revision=5145f4fbc15c401d1f6566c8c512821cc551bc43
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)
helper="$root/tools/rehearse_immutable_ios_maven.py"
work=$(mktemp -d "${TMPDIR:-/tmp}/madcore-ios-immutable.XXXXXXXX" 2>/dev/null)
exec >"$work/private.log" 2>&1
source="$work/source"

# Only fixed allowlisted labels can reach stdout or the CI job summary.
failure_code() {
    local log=$1 marker
    marker=$(grep -m1 -E '^MADCORE_IOS_REASON=(requested-version|source-layout|source-drift|manifest-version|stage-layout|metadata-layout|metadata-invalid|metadata-or-file-layout|pom-coordinates|pom-core-edge|pom-graph|gmm-coordinates|gmm-redirect|gmm-target-set|gmm-core-edge|artifact-layout|artifact-checksum|klib-layout|klib-zip|klib-manifest|klib-target|file-read|arguments)$' "$log" || :)
    if [[ -n "$marker" ]]; then
        printf '%s\n' "${marker#MADCORE_IOS_REASON=}"
    elif grep -Fq 'MADCORE_IOS_SELECTED_COORDINATES' "$log"; then
        echo selected-coordinates
    elif grep -Fq 'MADCORE_IOS_SELECTED_ARTIFACTS' "$log"; then
        echo selected-artifacts
    elif grep -Fq 'MADCORE_IOS_SELECTED_BYTES' "$log"; then
        echo selected-bytes
    elif grep -Fq 'Unexpected source project dependency' "$log"; then
        echo source-dependency
    elif grep -Eiq 'UnknownHostException|ConnectException|SocketTimeoutException|SSLHandshakeException|HTTP response code: (401|403|404|429|5[0-9]{2})' "$log"; then
        echo transport
    elif grep -Eiq 'Could not (resolve|find|download).*kotlin-native-prebuilt|Failed to download dependency for Kotlin Native' "$log"; then
        echo native-toolchain-resolution
    elif grep -Eiq '^> Task :[^[:space:]]*:compileKotlinIos(Arm64|SimulatorArm64) FAILED' "$log"; then
        echo native-compile-task
    elif grep -Eiq '^> Task :[^[:space:]]*:publish[^[:space:]]* FAILED' "$log"; then
        echo publication-task
    elif grep -Eiq '^> Task :[^[:space:]]*linkReleaseFrameworkIosSimulatorArm64 FAILED' "$log"; then
        echo umbrella-link-task
    elif grep -Eiq 'Could not (resolve|find)|No matching variant' "$log"; then
        echo dependency-resolution
    elif grep -Eiq '(cannot|could not) (locate|find) task|task .* not found' "$log"; then
        echo task-missing
    elif [[ "$stage" == independent-swift-link ]]; then
        if grep -Eiq '(error: no such module|error: could not build (Objective-C )?module)' "$log"; then
            echo swift-import
        elif grep -Eiq 'linker command failed|undefined symbols|fatal error:.*linker' "$log"; then
            echo swift-link
        else
            echo unclassified
        fi
    else
        echo unclassified
    fi
}
run_checked() {
    local log="$work/$stage.log"
    if "$@" >"$log" 2>&1; then
        return 0
    else
        stage="$stage-$(failure_code "$log")"
        return 1
    fi
}

if [[ ${2:-} != --prepare-only ]]; then
    stage=exact-transition
    test "$(git -C "$root" rev-parse HEAD^)" = "$revision"
    test "$(git -C "$root" diff --no-renames --name-status "$revision" HEAD)" = \
        $'A\t.github/workflows/phase4-ios-immutable-maven.yml\nA\ttools/rehearse_immutable_ios_maven.py\nA\ttools/rehearse_immutable_ios_maven.sh\nA\ttools/test_immutable_ios_maven_rehearsal.py'
fi

stage=locked-source
mkdir "$source"
git -C "$root" archive "$revision" | tar -xf - -C "$source"
run_checked python3 -B "$helper" prepare "$source" --expected-version "$version"
if [[ ${2:-} == --prepare-only ]]; then
    passed=true
    report 'iOS immutable storage rehearsal: exact-source preparation only; no build'
    exit 0
fi

stage=toolchain
test "$(uname -m)" = arm64
test "${DEVELOPER_DIR:-}" = /Applications/Xcode_26.0.1.app/Contents/Developer
test "$(xcodebuild -version)" = $'Xcode 26.0.1\nBuild version 17A400'
device_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
sim_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
test -d "$device_sdk"
test -d "$sim_sdk"
test -n "$(xcrun --sdk iphoneos --show-sdk-build-version)"
test -n "$(xcrun --sdk iphonesimulator --show-sdk-build-version)"
"${JAVA_HOME:?JDK 21 required}/bin/java" -version >"$work/jdk.log" 2>&1
grep -Eq 'version "21([."]|$)' "$work/jdk.log"
export GRADLE_USER_HOME="$work/gradle" KONAN_DATA_DIR="$work/konan"
mkdir "$GRADLE_USER_HOME"
printf '%s\n' 'org.gradle.java.installations.auto-download=false' >"$GRADLE_USER_HOME/gradle.properties"
stage=wrapper-files
cd "$source"
test -x ./gradlew
test -s gradle/wrapper/gradle-wrapper.jar
test -s gradle/wrapper/gradle-wrapper.properties
stage=wrapper-bootstrap
run_checked ./gradlew --no-daemon --console=plain --version
grep -Fxq 'Gradle 9.4.1' "$work/wrapper-bootstrap.log"
gradle=(./gradlew --no-daemon --console=plain)
stage=core-staging
core_repo="$source/build/staging-repository/ios"
test ! -e "$core_repo"
run_checked "${gradle[@]}" -Pmadcore.target=ios :core-storage:publishAllPublicationsToStagingRepository
stage=core-verification
run_checked python3 -B "$helper" verify-core "$core_repo" --manifest "$source/SDK-MODULES.json" --expected-version "$version"

stage=upper-staging
fixture="$source/examples/ios-kotlin-composition"
cp -R "$fixture/producers" "$work/producers"
cp -R "$fixture/umbrella" "$work/umbrella"
mkdir "$work/upper-repository" "$work/host"
cp "$fixture/host/App.swift" "$work/host/"
upper="$work/upper-repository"
run_checked "${gradle[@]}" -p "$work/producers" "-PmadcoreRepository=$core_repo" "-PupperRepository=$upper" \
    :upper-alpha:publishAllPublicationsToProbeRepository :upper-beta:publishAllPublicationsToProbeRepository
stage=upper-verification
run_checked python3 -B "$helper" verify-uppers "$upper" --expected-version "$version"

# The host's source and framework live outside all producer checkouts. Keep
# only actual Maven repositories as imports, not producer outputs or source.
rm -rf -- "$work/producers" "$fixture/producers" "$source/core-storage"
stage=selected-artifact-and-umbrella-link
run_checked "${gradle[@]}" -p "$work/umbrella" "-PmadcoreRepository=$core_repo" "-PupperRepository=$upper" \
    linkReleaseFrameworkIosSimulatorArm64
cp -R "$work/umbrella/build/bin/iosSimulatorArm64/releaseFramework/AppComposition.framework" "$work/host/"
rm -rf -- "$work/umbrella"
stage=independent-swift-link
cd "$work/host"
run_checked xcrun --sdk iphonesimulator swiftc -parse-as-library App.swift \
    -target arm64-apple-ios15.0-simulator -sdk "$sim_sdk" \
    -F "$work/host" -framework AppComposition -framework Foundation -framework UIKit \
    -Xlinker -ObjC -lc++ -Xlinker -no_adhoc_codesign -o CompositionHost
stage=independent-swift-output
test -s CompositionHost
passed=true
report 'iOS immutable storage rehearsal: six verified KLIBs and independent Swift simulator link; no signing, runtime or release'
