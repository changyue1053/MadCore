#!/usr/bin/env bash
# Disposable same-source comparison. No SDK installation, device, or upload.
set -euo pipefail
umask 077
[[ $# == 0 ]] || { echo 'Usage: bash tools/rehearse_android_packaged_abi.sh' >&2; exit 2; }
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-aar-rehearsal.XXXXXXXX")
source_sha=9555b58b3af91165e4a1a2a8db02ba3c1903c24a
overlay=.github/phase3/apply-official-toolchain.py
overlay_blob=7d190cbf5a68cb4f4f8ff0a388291d49ee3ca486
baseline_wrapper_blob=cbcbf0b9fae1d6d1650b11b4aa11725d211ec188
exec 3>&1
stage=setup
reported=false
report() { printf 'MADCORE_ANDROID_PACKAGED_REHEARSAL_STAGE=%s RESULT=%s\n' "$1" "$2" >&3; }
cleanup() {
    rm -rf -- "$work"
    if [[ "$reported" == false ]]; then report "$stage" failed; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
exec >"$work/rehearsal.log" 2>&1

stage=preinstalled-toolchain
[[ "$(uname -sm)" == "Linux x86_64" ]]
jdk=${JAVA_HOME:?set JAVA_HOME to the preinstalled JDK 21}
[[ "$("$jdk/bin/javac" -version 2>&1)" =~ ^javac\ 21(\.|$) ]]
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
test -n "$sdk" && test -s "$sdk/platforms/android-36/android.jar"
test -x "$sdk/build-tools/35.0.0/zipalign"
test -x "$sdk/build-tools/35.0.0/apksigner"
if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    test "$(realpath -e "$sdk")" = "$(realpath -e "$ANDROID_SDK_ROOT")"
fi
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
export ANDROID_USER_HOME="$work/android-user" TMPDIR="$work/tmp"
mkdir "$ANDROID_USER_HOME" "$TMPDIR"
report "$stage" passed

stage=locked-source
git -C "$root" cat-file -e "$source_sha^{commit}"
test "$(git -C "$root" rev-parse "$source_sha:$overlay")" = "$overlay_blob"
test "$(git -C "$root" rev-parse "$source_sha:gradle/wrapper/gradle-wrapper.properties")" = "$baseline_wrapper_blob"
for side in baseline candidate; do
    mkdir "$work/$side"
    git -C "$root" archive "$source_sha" | tar -xf - -C "$work/$side"
done
test "$(git -C "$root" hash-object "$work/candidate/$overlay")" = "$overlay_blob"
python3 -B "$work/candidate/$overlay"
# The archived evaluation wrapper predates checksum pinning. Add only its
# official distribution checksum in disposable scratch; no version changes.
python3 -B - "$work/baseline/gradle/wrapper/gradle-wrapper.properties" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = path.read_bytes()
match = b"gradle-9.4.1-bin.zip\n"
if data.count(match) != 1 or b"distributionSha256Sum" in data:
    raise SystemExit("unexpected baseline distribution declaration")
checksum = b"2ab2958f2a1e51120c326cad6f385153bb11ee93b3c216c5fccebfdfbb7ec6cb"
path.write_bytes(data.replace(match, match + b"distributionSha256Sum=" + checksum + b"\n"))
PY
report "$stage" passed

for side in baseline candidate; do
    stage="$side-assemble-release"
    export GRADLE_USER_HOME="$work/gradle-$side"
    mkdir "$GRADLE_USER_HOME"
    printf '%s\n' 'org.gradle.java.installations.auto-download=false' \
        'android.builder.sdkDownload=false' >"$GRADLE_USER_HOME/gradle.properties"
    (
        cd "$work/$side"
        ./gradlew --no-daemon --console=plain -Pmadcore.target=android \
            -Pandroid.builder.sdkDownload=false assembleRelease
    )
    report "$stage" passed
done

stage=compiler-control-and-packaged-comparison
# Keep the comparator unchanged. Only its disposable copy uses the JDK
# positive/negative control driver, with the same analyzer in the same process.
host="$work/tool-runner"
mkdir -p "$host/tools" "$host/gradle"
cp "$work/baseline/gradlew" "$work/baseline/SDK-MODULES.json" "$host/"
cp -R "$work/baseline/gradle/wrapper" "$host/gradle/"
cp "$root/tools/compare_android_packaged_abi.py" "$root/tools/compare_android_packaged_abi.sh" "$host/tools/"
analyzer=android-packaged-abi-analyzer
cp -R "$root/tools/$analyzer" "$host/tools/"
cp "$root/tools/android-packaged-abi-rehearsal/PackagedAarAbiWithControls.java" \
    "$host/tools/$analyzer/src/main/java/"
python3 -B - "$host/tools/$analyzer/build.gradle" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
main = "mainClass = 'PackagedAarAbi'"
if content.count(main) != 1:
    raise SystemExit("unexpected standalone analyzer entry")
path.write_text(content.replace(main, "mainClass = 'PackagedAarAbiWithControls'"), encoding="utf-8")
PY

set +e
RUNNER_TEMP="$work" bash "$host/tools/compare_android_packaged_abi.sh" \
    "$work/baseline" "$work/candidate" >"$work/result.log" 2>&1
result=$?
set -e
python3 -B - "$work/result.log" "$result" <<'PY' >&3
from pathlib import Path
import re
import sys

log = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
status = int(sys.argv[2])
inputs = [line for line in log if re.fullmatch(
    r"PACKAGED_ANDROID_AAR_INPUTS=9 BASELINE_CLASSES=[1-9][0-9]* CANDIDATE_CLASSES=[1-9][0-9]*", line)]
comparisons = [line for line in log if re.fullmatch(r"PACKAGED_ANDROID_AAR_ABI_EQUAL=[0-9]+ CHANGED=[0-9]+", line)]
if len(comparisons) == 1 and len(inputs) == 1:
    match = re.fullmatch(r"PACKAGED_ANDROID_AAR_ABI_EQUAL=([0-9]+) CHANGED=([0-9]+)", comparisons[0])
    if sum(int(count) for count in match.groups()) == 9:
        print("MADCORE_ANDROID_PACKAGED_REHEARSAL_STAGE=compiler-control RESULT=passed")
        print(inputs[0])
        print(comparisons[0])
        if status == 0 and match.groups() == ("9", "0"):
            raise SystemExit(0)
raise SystemExit(1)
PY
report "$stage" passed
reported=true
