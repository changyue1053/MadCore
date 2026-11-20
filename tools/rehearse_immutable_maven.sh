#!/usr/bin/env bash
# Local rehearsal only. Must not be used as a publication or iOS acceptance gate.
set -euo pipefail
usage() {
    echo 'Usage: bash tools/rehearse_immutable_maven.sh jvm|android X.Y.Z-rehearsal.N [--prepare-only]' >&2
    exit 2
}
[[ $# == 2 || ( $# == 3 && "$3" == --prepare-only ) ]] || usage
lane=$1
version=$2
case "$lane" in jvm|android) ;; *) usage ;; esac
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
revision=66a4789c14c1e9dfd5d3c7118ca90effc8c4e8b7
helper="$root/tools/rehearse_immutable_maven.py"
work=$(mktemp -d "${TMPDIR:-/tmp}/madcore-immutable-maven.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/source" "$work/tmp" "$work/gradle-home"
git -C "$root" archive "$revision" | tar -xf - -C "$work/source"
python3 -B "$helper" prepare "$work/source" --expected-version "$version"
if [[ ${3:-} == --prepare-only ]]; then exit 0; fi
export TMPDIR="$work/tmp" GRADLE_USER_HOME="$work/gradle-home"
printf '%s\n' 'org.gradle.java.installations.auto-download=false' > "$GRADLE_USER_HOME/gradle.properties"
if [[ "$lane" == android ]]; then
    sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    test -n "$sdk" && test -s "$sdk/platforms/android-36/android.jar" || {
        echo 'Requires already provisioned Android SDK 36; no installation attempted.' >&2
        exit 1
    }
    printf '%s\n' 'android.builder.sdkDownload=false' >> "$GRADLE_USER_HOME/gradle.properties"
fi
source="$work/source"
repository="$source/build/staging-repository/$lane"
test ! -e "$repository"
cd "$source"
./gradlew --no-daemon "-Pmadcore.target=$lane" publishAllPublicationsToStagingRepository
python3 -B "$helper" verify "$repository" --manifest "$source/SDK-MODULES.json" \
    --lane "$lane" --expected-version "$version"
if [[ "$lane" == jvm ]]; then
    cp -R examples/jvm-consumer "$work/jvm-app"
    ./gradlew --no-daemon -p "$work/jvm-app" "-PmadcoreRepository=$repository" run writeRuntimeClasspath
    python3 -B tools/check_jvm_classpath.py "$work/jvm-app/runtime-classpath.json"
else
    # This build-only fixture probes four classpaths and produces APKs without a
    # device. Its two release publications stay separate from the Core stage.
    bash tools/test_android_maven_consumer.sh "$repository" --build-only
    shopt -s nullglob
    upper=("$TMPDIR"/*/upper-maven)
    test "${#upper[@]}" -eq 1
    python3 -B "$helper" verify-android-uppers "${upper[0]}" --expected-version "$version"
fi
echo "$lane immutable Maven rehearsal passed (scratch only; no external publication)"
