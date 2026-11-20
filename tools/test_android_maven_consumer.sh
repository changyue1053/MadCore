#!/usr/bin/env bash
# Reproduce the independent Maven-only API30 app gate after staging Android Core.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
usage() {
  echo "Usage: bash tools/test_android_maven_consumer.sh /absolute/path/to/staging-repository/android [--connected-api24|--build-only] [--expected-version X.Y.Z-rehearsal.N]" >&2
  exit 2
}
[[ $# -ge 1 && "$1" == /* && -d "$1" ]] || usage
repository=$1
shift
mode=--managed-api30
snapshot=0.1.0-SNAPSHOT
expected=$snapshot
explicit_expected=false
while (( $# )); do
  case "$1" in
    --connected-api24|--build-only)
      [[ "$mode" == --managed-api30 ]] || usage
      mode=$1
      shift
      ;;
    --expected-version)
      [[ $# -ge 2 && "$explicit_expected" == false ]] || usage
      expected=$2
      explicit_expected=true
      shift 2
      ;;
    *) usage ;;
  esac
done
if [[ "$expected" != "$snapshot" ]]; then
  export LC_ALL=C
  component='(0|[1-9][0-9]*)'
  [[ ${#expected} -le 64 && "$expected" =~ ^$component\.$component\.$component-rehearsal\.[1-9][0-9]*$ ]] || usage
  # Do not expand the constrained hosted minimum-SDK probe's runtime scope.
  [[ "$mode" != --connected-api24 ]] || usage
fi
gradle_flags=("-PmadcoreExpectedCoreVersion=$expected")
if [[ "$expected" != "$snapshot" ]]; then
  gradle_flags+=(-Pandroid.builder.sdkDownload=false)
fi
test_task=:app:pixel2api30DebugAndroidTest
case "$mode" in
  --managed-api30) ;;
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
  if [[ "$expected" != "$snapshot" ]]; then
    sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
    image="$sdk/system-images/android-30/default/x86_64"
    if [[ "$(uname -sm)" != "Linux x86_64" || -z "$sdk" ||
          ! -s "$sdk/platforms/android-36/android.jar" ||
          ! -x "$sdk/build-tools/35.0.0/zipalign" ||
          ! -x "$sdk/emulator/emulator" || ! -x "$sdk/platform-tools/adb" ||
          ! -s "$image/package.xml" || ! -s "$image/system.img" ]]; then
      echo 'Fixed-version runtime requires an already installed API30 standard AOSP image and SDK36 tools' >&2
      exit 1
    fi
    if [[ -n "${ANDROID_SDK_ROOT:-}" && "$(realpath -e "$sdk")" != "$(realpath -e "$ANDROID_SDK_ROOT")" ]]; then
      echo 'Fixed-version runtime requires one consistent Android SDK root' >&2
      exit 1
    fi
  fi
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

./gradlew --no-daemon "${gradle_flags[@]}" -p "$upper" -PmadcoreRepository="$repository" \
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
  ./gradlew --no-daemon --no-configuration-cache "${gradle_flags[@]}" -p "$consumer" -PmadcoreRepository="$repository" \
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

# Only the disposable Debug app can trust the positive fixture. Make no change
# to production code, system trust, the source example or the release variant.
debug="$consumer/app/src/debug"
mkdir -p "$debug/res/raw" "$debug/res/xml"
ca="$debug/res/raw/madcore_fixture_ca.pem"
cat > "$debug/AndroidManifest.xml" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:networkSecurityConfig="@xml/madcore_fixture_network" />
</manifest>
EOF
cat > "$debug/res/xml/madcore_fixture_network.xml" <<'EOF'
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">10.0.2.2</domain>
        <trust-anchors>
            <certificates src="@raw/madcore_fixture_ca" />
        </trust-anchors>
    </domain-config>
</network-security-config>
EOF
python3 tools/http_fixture.py --tls --android-ca "$ca" > "$work/http-fixture.log" 2>&1 &
fixture=$!
cleanup_fixture() {
  kill "$fixture" 2>/dev/null || true
  wait "$fixture" 2>/dev/null || true
}
trap cleanup_fixture EXIT
if ! curl --noproxy '*' --fail --retry 5 --retry-connrefused --retry-max-time 30 \
     --max-time 5 http://127.0.0.1:18082/ok ||
   ! curl --noproxy '*' --fail --max-time 5 http://127.0.0.1:18082/tls-ready ||
   [[ "$(curl --noproxy '*' --fail --max-time 5 --cacert "$ca" \
     https://127.0.0.1:28443/ok)" != hello ]]; then
  tail -n 80 "$work/http-fixture.log"
  exit 1
fi
if [[ "$test_task" == :app:connectedDebugAndroidTest ]]; then
  adb="${ANDROID_HOME:?}/platform-tools/adb"
  # Recheck immediately before Gradle: never dispatch to another device.
  test "$(timeout 10 "$adb" devices | awk 'NR > 1 && NF {print $1, $2}')" = "$ANDROID_SERIAL device"
  test "$(timeout 10 "$adb" -s "$ANDROID_SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')" = 24
fi
./gradlew --no-daemon --no-configuration-cache "${gradle_flags[@]}" -p "$consumer" -PmadcoreRepository="$repository" \
  -PupperRepository="$upper_repo" :app:verifyPublishedComposition \
  :app:assembleDebug "$test_task"
python3 tools/check_android_results.py "$consumer/app/build/outputs/androidTest-results"
