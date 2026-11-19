# Independent Android artifact consumer

This separate Gradle build uses only staged Maven publications, not source project dependencies.
CI copies it outside the SDK checkout, assembles an APK, and executes instrumentation on a
Gradle-managed API 30 standard AOSP x86_64 device. It tests configuration plus actual HTTP GET, POST,
HTTP error status, redirect refusal, fixed/chunked size caps, timeout and subsequent request.

The fixture is the SDK's loopback-only tools/http_fixture.py on host port 18082.
The emulator reaches it through 10.0.2.2. Only the debug manifest permits cleartext;
production SDK defaults and the release manifest forbid it.

Use Gradle 9.4.1, JDK 21, Android SDK 36 and an available licensed API 30 standard AOSP x86_64 image:
`gradle -PmadcoreRepository=/absolute/path/to/staging-repository/android :app:pixel2api30DebugAndroidTest`

This is not physical-device, public-TLS, minimum-API or UI acceptance coverage.

Standard AOSP is intentional: its repository metadata references the existing Android SDK
license, unlike the separately licensed ATD image. CI does not auto-accept new agreements.
