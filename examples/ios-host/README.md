# Artifact-only iOS host smoke app

This test-only UIKit application is compiled outside the SDK checkout from the already-built
XCFramework. It runs in an actual iOS Simulator, executes Kotlin-exported configuration,
Foundation-backed storage and off-main NSURLSession HTTP calls, and must exit with an exact
success marker. It does not compile SDK sources or link a Gradle project.

Use tools/build_ios_xcframework.sh, boot a simulator, start tools/http_fixture.py, then set
MADCORE_IOS_SIMULATOR_UDID and run bash tools/test_ios_host.sh.

The app allows cleartext for the loopback test fixture via a deliberately permissive
test-only ATS manifest. Do not ship this manifest or app. Simulator signing is ad hoc, without
an Apple account, certificate or provisioning profile. No app is published.

Not a production UI, real-device test, App Store privacy approval, process-crash storage test,
or public-TLS validation. SDK privacy manifest resources are preserved in a named app resource
bundle so their inclusion is checked rather than assumed for a manually linked static framework.
