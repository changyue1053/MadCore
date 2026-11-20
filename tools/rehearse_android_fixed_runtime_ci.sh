#!/usr/bin/env bash
# One Draft transition; only a hosted, already-provisioned API30 emulator.
set -euo pipefail
umask 077
export LC_ALL=C
[[ $# == 0 || ( $# == 1 && "$1" == --preflight-only ) ]] || exit 2
status() { printf '%s\n' "MADCORE_ANDROID_FIXED_RUNTIME_STAGE=$1 RESULT=$2${3:+ REASON=$3}"; }
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
image="$sdk/system-images/android-30/default/x86_64"
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted ||
      "$(uname -sm)" != 'Linux x86_64' || -z "$sdk" ||
      ! -s "$sdk/platforms/android-36/android.jar" ||
      ! -x "$sdk/build-tools/35.0.0/zipalign" ||
      ! -x "$sdk/build-tools/35.0.0/apksigner" ||
      ! -x "$sdk/emulator/emulator" || ! -x "$sdk/platform-tools/adb" ]]; then
    status preflight failed preinstalled-host-tools-required
    exit 1
fi
if [[ -n "${ANDROID_SDK_ROOT:-}" &&
      "$(realpath -e "$sdk" 2>/dev/null)" != "$(realpath -e "$ANDROID_SDK_ROOT" 2>/dev/null)" ]]; then
    status preflight failed conflicting-sdk-roots
    exit 1
fi
if [[ ! -s "$image/package.xml" || ! -s "$image/system.img" ]]; then
    status preflight failed preinstalled-api30-image-required
    exit 1
fi
if ! python3 -B - "$image/package.xml" 2>/dev/null <<'PY'
import sys
from xml.etree import ElementTree
root = ElementTree.parse(sys.argv[1]).getroot()
for item in root.iter():
    item.tag = item.tag.rsplit("}", 1)[-1]
packages = [item for item in root.iter("localPackage")
            if item.get("path") == "system-images;android-30;default;x86_64"]
raise SystemExit(0 if len(packages) == 1 and packages[0].findtext("revision/major") == "11" else 1)
PY
then
    status preflight failed pinned-api30-image-revision-required
    exit 1
fi
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
status preflight passed ""
if [[ ${1:-} == --preflight-only ]]; then exit 0; fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm || -n "${ANDROID_SERIAL:-}" ]]; then
    status emulator failed hosted-kvm-or-device-scope
    exit 1
fi

source_sha=0540aed86184de932545c9ff8ab22143a203c01b
expected=0.1.0-rehearsal.1
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-fixed-android.XXXXXXXX")
exec 3>&1
stage=archive
reported=false
cleanup() {
    rm -rf -- "$work"
    if [[ "$reported" == false ]]; then
        printf 'MADCORE_ANDROID_FIXED_RUNTIME_STAGE=%s RESULT=failed\n' "$stage" >&3
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
exec >"$work/rehearsal.log" 2>&1
source="$work/source"
export TMPDIR="$work/tmp" GRADLE_USER_HOME="$work/gradle-home"
export ANDROID_USER_HOME="$work/android-user" ANDROID_EMULATOR_HOME="$work/android-user"
export ANDROID_AVD_HOME="$work/avd"
mkdir "$source" "$TMPDIR" "$GRADLE_USER_HOME" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"
stage=emulator-scope
# The previous managed suite must leave no unrelated or stale ADB target.
devices=$(timeout 10 "$sdk/platform-tools/adb" devices)
test -z "$(awk 'NR > 1 && NF {print}' <<< "$devices")"
stage=archive
printf '%s\n' 'org.gradle.java.installations.auto-download=false' \
    'android.builder.sdkDownload=false' > "$GRADLE_USER_HOME/gradle.properties"
git -C "$root" archive "$source_sha" | tar -xf - -C "$source"
cd "$source"
python3 -B - SDK-MODULES.json "$expected" <<'PY'
from pathlib import Path
import json
import sys
path = Path(sys.argv[1])
expected = sys.argv[2]
raw = path.read_bytes()
old = b'"version": "0.1.0-SNAPSHOT"'
if raw.count(old) != 1 or json.loads(raw)["version"] != "0.1.0-SNAPSHOT":
    raise SystemExit("unexpected archived manifest")
updated = raw.replace(old, b'"version": "' + expected.encode("ascii") + b'"')
if json.loads(updated)["version"] != expected:
    raise SystemExit("could not set the disposable producer version")
path.write_bytes(updated)
PY
status "$stage" passed "" >&3

stage=publication-and-metadata
repository="$source/build/staging-repository/android"
test ! -e "$repository"
./gradlew --no-daemon --console=plain -Pmadcore.target=android -Pandroid.builder.sdkDownload=false \
    publishAllPublicationsToStagingRepository
verified=$(python3 -B tools/rehearse_immutable_maven.py verify "$repository" --manifest SDK-MODULES.json \
    --lane android --expected-version "$expected")
test "$verified" = 'android: verified 30 Gradle metadata files and 30 staged POMs'
status "$stage" passed "" >&3

stage=independent-managed-host
bash tools/test_android_maven_consumer.sh "$repository" --expected-version "$expected" >"$work/runtime.log" 2>&1
python3 -B - "$work/runtime.log" <<'PY'
from collections import Counter
from pathlib import Path
import sys
out = Counter(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines())
scopes = ("debugCompileClasspath", "debugRuntimeClasspath", "releaseCompileClasspath", "releaseRuntimeClasspath")
if not all(out[scope + ": one Android Core version through two published upper AARs"] == 1 for scope in scopes):
    raise SystemExit("missing or ambiguous selected classpath evidence")
if out["Independent Android emulator behavior: 8 required cases passed"] != 1:
    raise SystemExit("missing or ambiguous full Android runtime evidence")
PY
stage=upper-metadata
shopt -s nullglob
upper=("$TMPDIR"/*/upper-maven)
test "${#upper[@]}" -eq 1
verified=$(python3 -B tools/rehearse_immutable_maven.py verify-android-uppers "${upper[0]}" \
    --expected-version "$expected")
test "$verified" = 'Alpha/Beta Maven metadata request only the expected Core coordinate'
status "$stage" passed "" >&3
printf 'MADCORE_ANDROID_FIXED_RUNTIME_RESULT=passed API=30 CLASSPATHS=4 CASES=8 VERSION=%s\n' "$expected" >&3
reported=true
