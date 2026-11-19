# Bounded delivery checklist

The goal is a reusable Core for several new apps, not migration parity or an
unbounded feature list. The current production modules cover configuration,
logging, time, JSON, extension registration, resource ownership, HTTP and
non-secret string storage. Testkit is optional. No additional product feature is
required merely to make this foundation useful.

## Current evidence and supported scope

Reviewed implementation baseline for this status update: **e828305d121cf900502da708d448f33d7efcb645**.
[CI 44527158033](https://github.com/changyue1053/MadCore/actions/runs/44527158033)
passed Android and JVM; Harmony was intentionally skipped. iOS remained queued
then cancelled with no runner or steps, both initially and after one targeted retry.
This CI run is not fully green. **Harmony tool execution and local builds are paused**
pending SDK-license applicability review for reusable SDK development, not merely
binary redistribution. No further retry or Harmony run is implied by these docs.
The exact-head local iOS staging/consumer evidence below is narrower than full CI.

Historical verified four-job baseline: **6d5b5c6940d9d026ed68020c23aec5bcb65998a6**,
[CI 44463243979](https://github.com/changyue1053/MadCore/actions/runs/44463243979),
Android/iOS/JVM/Harmony all successful. Later commits require their own CI result;
this baseline does not claim a newer head has already passed. Its artifact listing
contains zero downloadable files. Handoff is source plus local build instructions,
not an attached/published SDK binary. Existing private HAPs are evaluation outputs.

- JVM: common behavior, published closure, artifact-only host and two upper JARs.
- Android: published AARs, two independent upper AARs and API30 emulator app behavior.
- iOS: device/simulator framework packaging, independent UIKit simulator host,
  real HTTP/TLS tests, two Kotlin upper libraries with one app umbrella.
- Historical Harmony CI (now paused): pinned API18 HAR/HAP, default and opt-in bridge compilation, native
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
   physical device. Android API24 and physical iOS/Harmony devices
   remain unverified. General version-skew compatibility is not established by
   any single consumer experiment. Do not expand the matrix without an app/release requirement.
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

## Exact-head local iOS staging consumer evidence

On 2026-11-19 UTC, all tracked blobs were verified against
`e828305d121cf900502da708d448f33d7efcb645` before and after isolated local testing.
Existing Xcode27.0 (27A266a) and Kotlin/Native2.2.21 were used; Gradle calls ran
offline against existing caches. This documentation update was excluded.

- Core storage published into `build/staging-repository/ios`, with both iOS
  variants in root metadata and no legacy unsuffixed Maven directory.
- Two independently published Kotlin2.2.21 upper KLIBs resolved that Core artifact.
  Producer source was removed before the separate umbrella resolved and linked;
  its existing published-input guard passed.
- The copied framework alone typechecked and linked the unchanged Swift host.
  A fresh disposable iPhone15/iOS17.5 arm64 simulator ran the existing 120-second
  gate, exited successfully and emitted exactly one `MADCORE_KOTLIN_COMPOSITION_PASS`.
  Type conversion, identity, cross-SDK mutation and host roundtrip assertions passed.
- Only ad-hoc simulator signing was used. The test app was uninstalled and the
  disposable simulator shut down/deleted. No credentials, account, upload or
  Harmony toolchain was used.

Host executable SHA256:
`096194bfa1dc0a9d986a444b53da9e00c1f4890bb4d44cb7c1e812a7b65ca2d1`.
Logs and evaluation artifacts remain private, not downloadable release assets.
This verifies the changed staging/consumer path, **not the full iOS CI suite**,
HTTP/TLS or physical-device execution. Test implementation:
[composition runner](../tools/test_ios_kotlin_composition.sh),
[host assertions](../examples/ios-kotlin-composition/host/App.swift).

## Tested toolchain versus upstream compatibility

Checked 2026-11-19 against JetBrains'
[Kotlin Multiplatform compatibility table](https://kotlinlang.org/docs/multiplatform/multiplatform-compatibility-guide.html)
and [Kotlin Gradle plugin support table](https://kotlinlang.org/docs/gradle-configure-project.html).
For Kotlin/KMP2.2.21 they list Gradle **7.6.3–8.14**, AGP **7.3.1–8.11.1**,
and the KMP table lists Xcode **26.0**.

This repository actually pins Kotlin2.2.21, Gradle9.4.1 and AGP8.13.2; the latter
two exceed those published fully supported ranges. The local iOS run above used
Xcode27.0, also not the Xcode version listed for Kotlin2.2.21. Passing scoped
builds/tests is project-specific evidence, **not an upstream-supported toolchain
claim or a general binary compatibility guarantee**. No versions or build behavior
are changed by this documentation. Agree a supported release toolchain and rerun
its acceptance matrix before expanding compatibility promises.
