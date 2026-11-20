#!/usr/bin/env bash
# Reproduce the independent Maven-only API30 app gate after staging Android Core.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
usage() {
  echo "Usage: bash tools/test_android_maven_consumer.sh /absolute/path/to/staging-repository/android [--connected-api24|--build-only]" >&2
  exit 2
}
if [[ $# -lt 1 || $# -gt 2 || "$1" != /* || ! -d "$1" ]]; then
  usage
fi
repository=$1
mode=--managed-api30
if [[ $# == 2 ]]; then mode=$2; fi
test_task=:app:pixel2api30DebugAndroidTest
case "$mode" in
  --managed-api30) [[ $# == 1 ]] || usage ;;
  --connected-api24)
    test "${GITHUB_ACTIONS:-}" = true
    test "${RUNNER_ENVIRONMENT:-}" = github-hosted
    test "${ANDROID_SERIAL:-}" = emulator-5580
    test_task=:app:connectedDebugAndroidTest
    ;;
  --build-only) ;;
  *) usage ;;
esac
if [[ "$mode" != --build-only ]]; then
  test -r /dev/kvm && test -w /dev/kvm || exit 1
fi
work=$(mktemp -d)
echo "Android Maven consumer diagnostics and test results: $work"
consumer="$work/consumer"
upper="$work/upper"
upper_repo="$work/upper-maven"
thin="$work/thin-aar"
mkdir -p "$consumer/app" "$upper/alpha" "$upper/beta" "$upper_repo" "$thin"

# Stage build files and source explicitly; no example Gradle cache, built AAR,
# local repository or machine-specific configuration can enter the host.
cp examples/android-consumer/{settings.gradle,gradle.properties} "$consumer/"
cp examples/android-consumer/app/build.gradle "$consumer/app/"
cp -R examples/android-consumer/app/src "$consumer/app/"
cp examples/android-upper-sdks/{build.gradle,settings.gradle} "$upper/"
for name in alpha beta; do
  cp "examples/android-upper-sdks/$name/build.gradle" "$upper/$name/"
  cp -R "examples/android-upper-sdks/$name/src" "$upper/$name/"
done

./gradlew --no-daemon -p "$upper" -PmadcoreRepository="$repository" \
  -PupperRepository="$upper_repo" \
  :alpha:publishReleasePublicationToUpperStagingRepository \
  :beta:publishReleasePublicationToUpperStagingRepository
for name in alpha beta; do
  publication="$upper_repo/example/madcore/upper/$name/0.1.0/$name-0.1.0"
  test -s "$publication.pom"
  test -s "$publication.module"
  cmp "$publication.aar" "$upper/$name/build/outputs/aar/$name-release.aar"
  cp "$publication.aar" "$thin/$name-release.aar"
done
python3 tools/check_upper_aars.py "$thin"
# Only Maven artifacts remain available. The app cannot reference the producer
# source or the raw AARs used for thinness checks.
rm -rf -- "$upper" "$thin"

if [[ "$mode" == --build-only ]]; then
  ./gradlew --no-daemon --no-configuration-cache -p "$consumer" -PmadcoreRepository="$repository" \
    -PupperRepository="$upper_repo" :app:verifyPublishedComposition \
    :app:assembleDebug :app:assembleDebugAndroidTest
  host="$consumer/app/build/outputs/apk/debug/app-debug.apk"
  instrumentation="$consumer/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
  test -s "$host" && test -s "$instrumentation" || exit 1
  (cd -- "$consumer/app/build/outputs/apk" &&
    sha256sum debug/app-debug.apk androidTest/debug/app-debug-androidTest.apk > "$work/apk-sha256.txt")
  printf '%s\n' "Build only: no device or instrumentation was run." \
    "Host: $host" "Instrumentation: $instrumentation" "Checksums: $work/apk-sha256.txt"
  exit 0
fi

python3 tools/http_fixture.py --tls > "$work/http-fixture.log" 2>&1 &
fixture=$!
cleanup_fixture() {
  kill "$fixture" 2>/dev/null || true
  wait "$fixture" 2>/dev/null || true
}
trap cleanup_fixture EXIT
if ! curl --fail --retry 5 --retry-connrefused http://127.0.0.1:18082/ok ||
   ! curl --fail http://127.0.0.1:18082/tls-ready; then
  tail -n 80 "$work/http-fixture.log"
  exit 1
fi
if [[ "$test_task" == :app:connectedDebugAndroidTest ]]; then
  adb="${ANDROID_HOME:?}/platform-tools/adb"
  # Recheck immediately before Gradle: never dispatch to another device.
  test "$(timeout 10 "$adb" devices | awk 'NR > 1 && NF {print $1, $2}')" = "$ANDROID_SERIAL device"
  test "$(timeout 10 "$adb" -s "$ANDROID_SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')" = 24
fi
./gradlew --no-daemon --no-configuration-cache -p "$consumer" -PmadcoreRepository="$repository" \
  -PupperRepository="$upper_repo" :app:verifyPublishedComposition \
  :app:assembleDebug "$test_task"
python3 tools/check_android_results.py "$consumer/app/build/outputs/androidTest-results"
