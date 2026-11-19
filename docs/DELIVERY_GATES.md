# Bounded delivery checklist

The goal is a reusable Core for several new apps, not migration parity or an
unbounded feature list. The current production modules cover configuration,
logging, time, JSON, extension registration, resource ownership, HTTP and
non-secret string storage. Testkit is optional. No additional product feature is
required merely to make this foundation useful.

## Current evidence and supported scope

Last verified four-job baseline: **a0b32ad2811018d694534036c434062e38658ad4**,
[CI 44460946700](https://github.com/changyue1053/MadCore/actions/runs/44460946700),
Android/iOS/JVM/Harmony all successful. Later commits require their own CI result;
this baseline does not claim a newer head has already passed.

- JVM: common behavior, published closure, artifact-only host and two upper JARs.
- Android: published AARs, two independent upper AARs and API30 emulator app behavior.
- iOS: device/simulator framework packaging, independent UIKit simulator host,
  real HTTP/TLS tests, two Kotlin upper libraries with one app umbrella.
- Harmony CI: pinned API18 HAR/HAP, default and opt-in bridge compilation, native
  link and host sanitizer/mock checks. CI does not run a Harmony device.
- Harmony manual runtime: Pura90 arm64/API23, SDK26.0.0.105 host with the separately
  pinned CPF native toolchain. Native smoke, ArkTS RCP policies/TLS rejection,
  Preferences process-restart checks and two independent upper HARs passed.
  See [runtime evidence](HARMONY_RUNTIME_EVIDENCE.md) for exact limits.
- Experimental Harmony Kotlin HTTP: real copied Kotlin→C→RCP→C→Kotlin results,
  eleven HTTP/TLS scenarios, close/late/stale-ID isolation and eight accepted-Promise
  quota recovery passed. The network-free Worker cleanup test additionally checks
  four-session C registry reclamation after actual Worker environment destruction.
  Details and artifact hashes: [experiment evidence](HARMONY_ASYNC_HTTP_EXPERIMENT.md).

## Finite remaining delivery gates

1. **Supported API boundary and lifetime:** keep the copied HTTP bridge opt-in until
   its production host integration and teardown contract are approved. Its value-ID
   detachment and bounded C state are distinct from RCP quiescence. Worker cleanup
   testing uses queued, undispatched requests; it does not prove teardown during
   active RCP callbacks. Started calls retain `isDrained=false`; neither elapsed
   time nor Promise settlement is presented as native callback drain.
2. **Storage scope:** real Harmony Preferences is verified as an ArkTS API. There
   is no persistent Harmony adapter implementing Kotlin `StringStore` across the
   runtime boundary. Require that adapter only if the release promises shared
   Kotlin persistence; otherwise document host-owned ArkTS integration explicitly.
3. **Device/compatibility matrix:** choose actual supported minimum platforms.
   API18 Harmony compilation is not API18 runtime proof; API23 emulator is not a
   physical device. Android API24, physical iOS/Harmony devices and version skew
   remain unverified. Do not expand the matrix without an app/release requirement.
4. **Distribution evidence:** select the project license and confirm source rights;
   inventory exact linked/copied runtime components, applicable licenses and NOTICE
   texts. Pinned SDK tool-use approval and public source visibility do not settle
   binary redistribution. See [distribution review](DISTRIBUTION_REVIEW.md).
5. **Release decision:** choose version, artifact destination and compatibility
   policy, then obtain explicit merge/release approval. Current snapshot/Draft PR
   and private test HAPs are evaluation outputs; no public binary release is approved.

No new product feature is required merely to close these gates. Scope can exclude
experimental networking rather than imply unverified three-platform parity.

## Evidence discipline

Native XML gates require exact test identities and reject absent, skipped, failed,
malformed and duplicate failure evidence. Tests of these gates run with Python
optimization both on and off. These checks do not authenticate arbitrary external
XML or make old local outputs fresh. Exact-head CI, API18 compile, API23 manual
runtime and physical-device coverage must remain separate. Historical commits in
other design documents describe their own stage, not superseding current status.

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
