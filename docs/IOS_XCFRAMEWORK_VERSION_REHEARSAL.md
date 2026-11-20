# Verify the full iOS XCFramework version at runtime

The regular, independent Swift simulator app compares
MadCoreInfo.shared.version to the exact expected value injected into its
disposable App Info.plist. By default the harness uses the checked-out producer
manifest, not the built framework, generated code, or its bundle version.
The terminal success still requires all original host checks. A missing or
wrong expectation emits a fixed mismatch marker and fails the app.

## One non-snapshot rehearsal (plan, not runtime evidence)

Use only a previously approved hosted simulator and the existing
test-only simulator signing/launch path. Do not use an attached physical
device, buy or add tooling, distribute binaries, or change the version
in the normal checkout.

1. In a fresh scratch archive of the exact reviewed commit containing this
   gate, change only SDK-MODULES.json's version from the checked-in snapshot
   to an explicitly chosen rehearsal token (for example 0.1.0-rehearsal.1,
   not a selected release). Reject pre-existing outputs. Keep isolated
   GRADLE_USER_HOME and KONAN_DATA_DIR in that scratch process; export both
   before running any Gradle wrapper and use the approved installed Xcode/SDK.
2. Run bash tools/build_ios_xcframework.sh, require both packaged arm64
   slices and test-stage privacy manifests. Use the existing CI HTTP
   loopback fixture/healthy simulator preflight; set the exact authorized
   MADCORE_IOS_SIMULATOR_UDID, not a physical-device identifier.
3. Run bash tools/test_ios_host.sh --expected-version "$rehearsal_token"
   against the new immutable scratch XCFramework. Require one
   MADCORE_HOST_VERSION_MATCH plus the original final app success, with the
   existing control app also successful.
4. Optional bounded negative control on the same scratch simulator: use a
   different explicit exact expected token without rebuilding or replacing
   the framework. Require version mismatch and host failure, with no host
   success marker. A generic launch/fixture error is not that control.
   Restore/remove the disposable test apps and scratch fixtures after use.

A passing result covers the linked **simulator** slice of the full XCFramework,
not physical-device runtime, app-store signing, Maven KLIB release, or
public distribution. Nothing in this plan changes the producer's version
authority, packaged API, or published artifact naming.
