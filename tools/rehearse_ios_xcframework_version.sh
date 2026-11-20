#!/usr/bin/env bash
# CI-only one-shot: no release, hardware, or distribution signing.
set -euo pipefail
revision=0540aed86184de932545c9ff8ab22143a203c01b
producer_token=0.1.0-rehearsal.1
expected_token=0.1.0-rehearsal.1  # Independent expectation, never read from a built file.
wrong_token=0.1.0-rehearsal.2
runtime=com.apple.CoreSimulator.SimRuntime.iOS-18-5
device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro
stage=hosted-runner
work=
udid=
fixture_pid=
done_rehearsal=false
exec 3>&1
report() {
    printf '%s\n' "$1" >&3
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
    fi
}
bounded() {
    python3 -B - "$@" <<'PY'
import os, signal, subprocess, sys
proc = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(proc.wait(timeout=int(sys.argv[1])))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            break
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
    sys.exit(124)
PY
}
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$fixture_pid" ]]; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
    fi
    if [[ -n "$udid" ]]; then
        bounded 25 xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        if ! bounded 30 xcrun simctl delete "$udid" >/dev/null 2>&1; then
            stage=simulator-cleanup
            status=1
        fi
    fi
    if [[ -n "$work" ]] && ! rm -rf -- "$work"; then
        stage=scratch-cleanup
        status=1
    fi
    if [[ "$done_rehearsal" == true && "$status" == 0 ]]; then
        report 'iOS XCFramework rehearsal: both slices packaged; Swift simulator match/behavior passed; wrong expectation rejected before behavior'
    else
        report "iOS XCFramework rehearsal incomplete ($stage)"
        if [[ "$status" == 0 ]]; then status=1; fi
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test "$#" -eq 0
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)
work=$(mktemp -d "${RUNNER_TEMP:?Hosted runner temp required}/madcore-ios-xc-version.XXXXXXXX")
exec >"$work/private.log" 2>&1

stage=exact-transition
test "$(git -C "$root" rev-parse HEAD^)" = "$revision"
test "$(git -C "$root" diff --no-renames --name-status "$revision" HEAD)" = \
    $'A\t.github/workflows/phase4-ios-xcframework-version.yml\nM\t.github/workflows/validate.yml\nA\ttools/rehearse_android_fixed_runtime_ci.sh\nA\ttools/rehearse_ios_xcframework_version.sh'
stage=apple-toolchain-and-simulator
test "$(uname -m)" = arm64
test "${DEVELOPER_DIR:-}" = /Applications/Xcode_16.4.app/Contents/Developer
test "$(xcodebuild -version)" = $'Xcode 16.4\nBuild version 16F6'
"${JAVA_HOME:?JDK21 required}/bin/java" -version >"$work/jdk.log" 2>&1
grep -Eq 'version "21([."]|$)' "$work/jdk.log"
for sdk in iphoneos iphonesimulator; do
    test -d "$(xcrun --sdk "$sdk" --show-sdk-path)"
    test -n "$(xcrun --sdk "$sdk" --show-sdk-build-version)"
done
bounded 20 xcrun simctl list -j >"$work/sim-inventory.json"
python3 -B - "$work/sim-inventory.json" "$runtime" "$device_type" <<'PY'
import json, sys
with open(sys.argv[1], 'rb') as f:
    data = json.load(f)
if len([v for v in data['runtimes'] if v['identifier'] == sys.argv[2] and v['isAvailable']]) != 1:
    sys.exit('Pinned iOS runtime unavailable')
if len([v for v in data['devicetypes'] if v['identifier'] == sys.argv[3]]) != 1:
    sys.exit('Pinned device type unavailable')
PY

stage=manifest-only-overlay
mkdir "$work/source"
git -C "$root" archive "$revision" | tar -xf - -C "$work/source"
cd "$work/source"
python3 -B - "$producer_token" <<'PY'
import hashlib, json, sys
from pathlib import Path
file = Path('SDK-MODULES.json')
value = file.read_bytes()
git_blob = hashlib.sha1(f'blob {len(value)}\0'.encode() + value).hexdigest()
pin = b'"version": "0.1.0-SNAPSHOT"'
if git_blob != 'c085a81db2a801eb7c522082ba0886a245ad7721' or value.count(pin) != 1:
    sys.exit('Unexpected pinned manifest')
expected = dict(json.loads(value), version=sys.argv[1])
overlay = value.replace(pin, b'"version": ' + json.dumps(sys.argv[1]).encode())
if json.loads(overlay) != expected:
    sys.exit('Unexpected manifest-only overlay')
file.write_bytes(overlay)
PY

stage=xcframework-build
export GRADLE_USER_HOME="$work/gradle" KONAN_DATA_DIR="$work/konan"
mkdir "$GRADLE_USER_HOME"
printf '%s\n' 'org.gradle.java.installations.auto-download=false' >"$GRADLE_USER_HOME/gradle.properties"
xc=madcore/build/XCFrameworks/release/MadCore.xcframework
test ! -e "$xc"
bash tools/build_ios_xcframework.sh

stage=xcframework-package
digest_xcframework() {
    local slice base
    test -s "$xc/Info.plist" || return 1
    shasum -a 256 "$xc/Info.plist" || return 1
    for slice in ios-arm64 ios-arm64-simulator; do
        base="$xc/$slice/MadCore.framework"
        test -s "$base/MadCore" && test -s "$base/PrivacyInfo.xcprivacy" &&
            test -s "$base/Headers/MadCore.h" || return 1
        shasum -a 256 "$base/MadCore" "$base/PrivacyInfo.xcprivacy" "$base/Headers/MadCore.h" || return 1
    done
}
digest_xcframework >"$work/original-artifact.sha256"

stage=loopback-fixture
python3 -B tools/http_fixture.py --tls >"$work/fixture.log" 2>&1 &
fixture_pid=$!
test "$(curl --noproxy '*' --fail --silent --show-error --retry 5 --retry-connrefused \
    --retry-max-time 25 --max-time 6 http://127.0.0.1:18082/ok)" = hello
test "$(curl --noproxy '*' --fail --silent --show-error --max-time 6 http://127.0.0.1:18082/tls-ready)" = ready
kill -0 "$fixture_pid"

stage=disposable-simulator
new_udid=$(bounded 30 xcrun simctl create "MadCore XCFramework version rehearsal" "$device_type" "$runtime")
[[ "$new_udid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
udid=$new_udid
bounded 45 xcrun simctl boot "$udid"
bounded 330 xcrun simctl bootstatus "$udid" -b
bounded 20 xcrun simctl list devices available -j >"$work/selected.json"
python3 -B - "$work/selected.json" "$runtime" "$device_type" "$udid" <<'PY'
import json, sys
with open(sys.argv[1], 'rb') as f:
    data = json.load(f)['devices']
matches = [(runtime, row) for runtime, rows in data.items() for row in rows if row['udid'] == sys.argv[4]]
if len(matches) != 1 or matches[0][0] != sys.argv[2] or matches[0][1].get('state') != 'Booted' \
        or matches[0][1].get('deviceTypeIdentifier') != sys.argv[3]:
    sys.exit('Expected exactly the newly created, pinned booted simulator')
PY
export MADCORE_IOS_SIMULATOR_UDID="$udid"

one() { [[ "$(grep -Fxc "$2" "$1" || true)" == 1 ]]; }
none() { [[ -f "$1" ]] && ! grep -Fxq "$2" "$1"; }
mkdir "$work/positive" "$work/negative"
stage=match-host
kill -0 "$fixture_pid"
RUNNER_TEMP="$work/positive" bounded 300 bash tools/test_ios_host.sh --expected-version "$expected_token" \
    >"$work/match.log" 2>&1
stage=match-markers
positive="$work/positive/madcore-ios-host.log"
one "$work/positive/madcore-ios-control.log" MADCORE_CONTROL_PASS
for marker in MADCORE_HOST_STAGE_APP_LAUNCH MADCORE_HOST_VERSION_MATCH MADCORE_HOST_STAGE_CHECKS \
              MADCORE_HOST_STAGE_HTTP MADCORE_SHARED_UPPER_SDKS_PASS MADCORE_EXTERNAL_IOS_HOST_PASS; do
    one "$positive" "$marker"
done
none "$positive" MADCORE_HOST_VERSION_MISMATCH
none "$positive" MADCORE_EXTERNAL_IOS_HOST_FAIL

stage=same-artifact-before-mismatch
digest_xcframework >"$work/before-negative.sha256"
cmp -s "$work/original-artifact.sha256" "$work/before-negative.sha256"
stage=mismatch-host-expected-rejection
kill -0 "$fixture_pid"
negative_status=0
RUNNER_TEMP="$work/negative" bounded 300 bash tools/test_ios_host.sh --expected-version "$wrong_token" \
    >"$work/mismatch.log" 2>&1 || negative_status=$?
test "$negative_status" -eq 1
stage=mismatch-markers
negative="$work/negative/madcore-ios-host.log"
one "$work/negative/madcore-ios-control.log" MADCORE_CONTROL_PASS
for marker in MADCORE_HOST_STAGE_APP_LAUNCH MADCORE_HOST_VERSION_MISMATCH MADCORE_EXTERNAL_IOS_HOST_FAIL; do
    one "$negative" "$marker"
done
for marker in MADCORE_HOST_VERSION_MATCH MADCORE_HOST_STAGE_CHECKS MADCORE_HOST_STAGE_HTTP \
              MADCORE_SHARED_UPPER_SDKS_PASS MADCORE_EXTERNAL_IOS_HOST_PASS; do
    none "$negative" "$marker"
done
stage=same-artifact-after-mismatch
digest_xcframework >"$work/after-negative.sha256"
cmp -s "$work/original-artifact.sha256" "$work/after-negative.sha256"
done_rehearsal=true
