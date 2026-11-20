# Independent Android artifact consumer

This standalone app declares only `example.madcore.upper:alpha:0.1.0` and
`example.madcore.upper:beta:0.1.0`. These are local, development-only Android
release Maven publications, not external package coordinates. Each upper SDK
declares Core as a transitive API dependency. The app has no raw AAR or direct
Core dependency. Its eight API30 instrumentation cases cover the upper libraries'
shared store identity and mutation, HTTP policy, TLS 1.2 success and untrusted TLS rejection,
storage and lifecycle.

## Reproduce the API30 gate

Use a Linux x86_64 host with accessible KVM, JDK 21, Android SDK 36, and an available
API 30 standard AOSP x86_64 image whose applicable license is already accepted.
Use the repository's Gradle 9.4.1 wrapper; Python 3, OpenSSL and curl must be available.
This procedure does not accept licenses or change KVM/system permissions.

From the MadCore repository root:

```bash
./gradlew --no-daemon -Pmadcore.target=android assembleRelease publishAllPublicationsToStagingRepository
python3 tools/check_publication_graph.py build/staging-repository/android
bash tools/test_android_maven_consumer.sh "$PWD/build/staging-repository/android"
```

The script publishes the two upper release components into a separate temporary
Maven repository, requires their POMs and Gradle module metadata, and checks the
published AARs against their thin release build outputs. It removes temporary upper
sources and loose AARs before the independently copied app is built. The Gradle gate
checks Debug and Release compile/runtime classpaths for one Android Core artifact
per production module at one version, with no JVM fallback.

The temporary directory is retained for diagnostics; the script stops only its own
fixture. Ensure host ports 18082, 18443 and 28443 are free before starting.
All fixtures bind host loopback: HTTP on 18082, an untrusted TLS endpoint on
18443 and an independently signed TLS 1.2 endpoint on 28443. The emulator reaches
them via `10.0.2.2`. The negative check requires increased connection attempts
and no accepted request; the positive check requires HTTP 200, the expected body,
and a matching accepted request through the same published Android transport.
The host prechecks the trusted endpoint with its public CA and normal hostname
verification. Fixture keys remain in private temporary directories and are
removed at teardown.

The runtime runner generates network policy only in its disposable Debug
source tree. Only the exact emulator alias can use the temporary CA or
fixture cleartext; other addresses have system trust and deny cleartext.
The original example and release variant are unchanged. Standard AOSP is intentional: its repository metadata
references the existing Android SDK license, unlike the separately licensed ATD image.
Do not accept new agreements implicitly to reproduce this lane.

This is not physical-device, public-TLS, minimum-API or UI acceptance coverage.

## Separate minimum-runtime probe (API24)

The Draft validation branch also has a clearly separate hosted API24 probe after
the default API30 gate. It requires the API30 runner's existing KVM and emulator,
an exact official AOSP x86_64 API24 package, and an already accepted matching
Android SDK license fingerprint. It fails closed if the package/terms cannot be
verified; it does not accept new terms. The preflight reports the official
manifest hash, expected license fingerprint and the shape of the existing
acceptance file, not the agreement text or the file contents. No label or
third-party Actions are needed for the Draft branch's normal pull-request CI.

The probe creates fresh AVD state, verifies its name, device set, ABI and
`ro.build.version.sdk=24`, and runs the same independent Maven app and eight
assertions via `:app:connectedDebugAndroidTest`. This is not a Gradle-managed API24
device; API30 continues to use the unchanged managed device. Check the separate
step and its exact-commit tests before interpreting API24 as runtime evidence.

## Prepare the two APKs without a device

Use a Linux build host with the same JDK 21 and Android SDK 36 build tooling,
and the locally staged Android Maven repository from the steps above. No system
image, KVM, emulator, ADB target or HTTP fixture is needed for this mode.

```bash
bash tools/test_android_maven_consumer.sh "$PWD/build/staging-repository/android" --build-only
```

The same thin-upper and Maven classpath checks run. The script builds the
Debug host and its matching instrumentation APK, prints their paths and writes
`apk-sha256.txt` in the temporary directory. Keep these local test outputs
private. Assembly alone does not count as an Android runtime or API24 result.
The build-only app has no temporary fixture trust and is not a substitute for
the full device runner. This mode never dispatches to a device and does not
change the separate CI probe's restrictions.
