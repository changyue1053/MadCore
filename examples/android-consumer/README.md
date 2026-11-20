# Independent Android artifact consumer

This standalone app declares only `example.madcore.upper:alpha:0.1.0` and
`example.madcore.upper:beta:0.1.0`. These are local, development-only Android
release Maven publications, not external package coordinates. Each upper SDK
declares Core as a transitive API dependency. The app has no raw AAR or direct
Core dependency. Its seven API30 instrumentation cases cover the upper libraries'
shared store identity and mutation, HTTP policy and untrusted TLS rejection,
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
fixture. Ensure host ports 18082 and 18443 are free before starting.
The fixture binds loopback only: HTTP on 18082 and a self-signed TLS endpoint on 18443.
The emulator reaches them via `10.0.2.2`. The TLS check requires a connection
attempt to the real fixture with no accepted HTTP request, not merely a missing server.

Only the debug manifest permits fixture cleartext; production SDK defaults and the
release manifest forbid it. Standard AOSP is intentional: its repository metadata
references the existing Android SDK license, unlike the separately licensed ATD image.
Do not accept new agreements implicitly to reproduce this lane.

This is not physical-device, public-TLS, minimum-API or UI acceptance coverage.
