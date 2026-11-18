# Bounded delivery checklist

The goal is a reusable Core for several new apps, not migration parity or an
unbounded feature list. The current production modules cover configuration,
logging, time, JSON, extension registration, resource ownership, HTTP and
non-secret string storage. Testkit is optional. No additional product feature is
required merely to make this foundation useful.

## What the current validation establishes

- JVM: common behavior, published dependency closure and an artifact-only host.
- Android: published AARs and independent app behavior on API30 emulator.
- iOS: device/simulator framework packaging, native behavior and an independent
  UIKit simulator host using only the framework and privacy resource.
- Harmony: native link, NAPI host-stub sanitizer tests, exact ArkTS source tests
  with mocked backends, real API18 HAR and outside consumer/unsigned HAP builds.

Native XML evidence gates require exact class/method identities and reject absent,
skipped, failed or malformed evidence, including duplicate failed attempts and
suite-reported failures. Negative fixtures run with and without Python optimization.
CI uses clean checkouts; these gates do not authenticate externally supplied XML
or establish freshness when manually rerun over an old local build directory.

## Remaining delivery gates (not extra features)

1. **Harmony runtime:** load the built native library and run the committed native
   smoke cases, RCP network/redirect/TLS tests and Preferences persistence tests on
   an authorized compatible device/emulator. Current CI does not provide this.
2. **Cross-runtime scope:** Kotlin/ArkTS asynchronous HTTP/storage bridging is
   design-only. Until implemented and runtime-tested, integrate the independent
   ArkTS APIs directly. Do not promise Kotlin API parity in a Harmony app.
3. **Distribution review:** resolve applicable licenses and notices before public
   binary release; source publication is not a license-clearance assertion.
4. **Release decision:** select a version, artifact destination and compatibility
   policy, then obtain explicit merge/release approval. Current snapshots and
   draft PR are evaluation outputs, not a stable release.

API24 Android runtime, physical iOS devices, wider OS matrices and additional TLS
negative scenarios remain coverage limits, not silently passed checks. See
PUBLIC_API_STATUS.md and CROSS_RUNTIME_BRIDGE.md. They should be prioritized by
new apps' actual minimum platforms and integration needs rather than invented
feature parity with a previous application.

## iOS runner diagnostics

Native test binaries are linked before simulator startup. Boot has its own bounded
10-minute infrastructure step; behavior retains its 15-minute limit and UIKit
host launch retains its 120-second limit. The overall job remains 35 minutes.
Host launch output is saved in the runner temporary directory and printed on
success, failure and timeout, including fixed non-sensitive app/check/HTTP stage
markers. A timeout fails even if a success marker was printed before hanging.
This improves diagnosis, not the platform coverage claim; CI logs retain emitted
failure evidence, while the temporary file itself is not a downloadable artifact.

The iOS fixture is now generated and made ready before simulator boot, with its
existing certificate-generation deadline and readiness retries unchanged. Behavior
steps recheck process liveness and TLS readiness, and an always-run cleanup stops
the ephemeral service. This addresses startup ordering after observed stalls in
certificate generation; it does not prove the historical stall's root cause.
