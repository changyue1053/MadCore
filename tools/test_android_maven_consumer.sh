#!/usr/bin/env bash
# Reproduce the independent Maven-only API30 app gate after staging Android Core.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
if [[ $# != 1 || "$1" != /* || ! -d "$1" ]]; then
  echo "Usage: bash tools/test_android_maven_consumer.sh /absolute/path/to/staging-repository/android" >&2
  exit 2
fi
repository=$1
test -r /dev/kvm && test -w /dev/kvm
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
./gradlew --no-daemon --no-configuration-cache -p "$consumer" -PmadcoreRepository="$repository" \
  -PupperRepository="$upper_repo" :app:verifyPublishedComposition \
  :app:assembleDebug :app:pixel2api30DebugAndroidTest
python3 tools/check_android_results.py "$consumer/app/build/outputs/androidTest-results"
