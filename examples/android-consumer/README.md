# Independent Android artifact consumer

This separate Gradle build consumes staged Core Maven publications plus two physical
upper-SDK AARs, not SDK source project dependencies. Its seven instrumentation tests
cover configuration/HTTP policy and untrusted TLS rejection, storage/persistence and
namespaces/error redaction, lifecycle, and two upper AARs sharing one Core instance.

## Reproduce the existing CI lane

Use a Linux x86_64 host with accessible KVM, JDK 21, Android SDK 36, and an available
API 30 standard AOSP x86_64 image whose applicable license is already accepted.
Use the repository's Gradle 9.4.1 wrapper; Python 3, OpenSSL and curl must be available.
This procedure does not accept licenses or change KVM/system permissions.

Run the following in **Bash from the MadCore repository root**, not this example directory.
The standalone app requires both `app/libs/alpha-release.aar` and
`app/libs/beta-release.aar`; simply running its instrumentation task before preparing
those artifacts and the Maven repository is insufficient.

```bash
(
set -euo pipefail
test -r /dev/kvm && test -w /dev/kvm
root="$PWD"
repository="$root/build/staging-repository/android"

./gradlew --no-daemon -Pmadcore.target=android assembleRelease publishAllPublicationsToStagingRepository
python3 tools/check_publication_graph.py "$repository"

work=$(mktemp -d)
echo "Consumer artifacts, fixture log and test results: $work"
consumer="$work/consumer"
upper="$work/upper"
mkdir -p "$consumer" "$upper"
cp -R examples/android-consumer/. "$consumer/"
cp -R examples/android-upper-sdks/. "$upper/"

./gradlew --no-daemon -p "$upper" -PmadcoreRepository="$repository" assembleRelease
mkdir -p "$consumer/app/libs"
cp "$upper/alpha/build/outputs/aar/alpha-release.aar" "$consumer/app/libs/"
cp "$upper/beta/build/outputs/aar/beta-release.aar" "$consumer/app/libs/"
python3 tools/check_upper_aars.py "$consumer/app/libs"
# The app must consume the copied AARs, not upper-SDK source projects.
rm -rf -- "$upper"

python3 tools/http_fixture.py --tls > "$work/http-fixture.log" 2>&1 &
fixture=$!
cleanup_fixture() {
  kill "$fixture" 2>/dev/null || true
  wait "$fixture" 2>/dev/null || true
}
trap cleanup_fixture EXIT
curl --fail --retry 5 --retry-connrefused http://127.0.0.1:18082/ok
curl --fail http://127.0.0.1:18082/tls-ready

./gradlew --no-daemon -p "$consumer" -PmadcoreRepository="$repository" :app:assembleDebug :app:pixel2api30DebugAndroidTest
python3 tools/check_android_results.py "$consumer/app/build/outputs/androidTest-results"
)
```

The temporary directory is retained for diagnostics; the trap stops only this command's
fixture process. Ensure host ports 18082 and 18443 are free before starting.
The fixture binds loopback only: HTTP on 18082 and a self-signed TLS endpoint on 18443.
The emulator reaches them via `10.0.2.2`. **Keep `--tls`**: the TLS rejection test
also checks that the fixture received a connection attempt and no accepted HTTP request;
a missing TLS server is not equivalent evidence. No trust bypass is used.

Only the debug manifest permits fixture cleartext; production SDK defaults and the
release manifest forbid it. Standard AOSP is intentional: its repository metadata
references the existing Android SDK license, unlike the separately licensed ATD image.
Do not accept new agreements implicitly to reproduce this lane.

This is not physical-device, public-TLS, minimum-API or UI acceptance coverage.
