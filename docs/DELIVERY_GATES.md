# Bounded delivery checklist

The goal is a reusable Core for several new apps, not migration parity or an
unbounded feature list. The current production modules cover configuration,
logging, time, JSON, extension registration, resource ownership, HTTP and
non-secret string storage. Testkit is optional. No additional product feature is
required merely to make this foundation useful.

## Current evidence and supported scope

Latest completed CI baseline before the acceptance-hardening work:
[`9b8b8fe1`, run 44668976044](https://github.com/changyue1053/MadCore/actions/runs/44668976044).
JVM and iOS passed. Android passed all seven independent Maven-consumer checks
on API30. The separate API24 image license fingerprint preflight then failed
before installation or boot, so the Android job and overall run are not green;
this is not an API24 runtime failure. Harmony was intentionally skipped. **Harmony
tool execution and local builds remain paused** pending license applicability
review for reusable SDK development, not merely binary redistribution.
These results apply to that exact commit, not to later edits.

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

## Execution plan and release gates

One release candidate is in scope: a stable foundation consumed as artifacts by
new apps and upper SDKs, with an explicit platform capability matrix. Do not
grow the module list or pull in product services to close the current release.

| Phase | Work | Exit evidence |
| --- | --- | --- |
| 1. Make acceptance repeatable | Isolate Android consumer APK assembly from device provisioning. Record iOS simulator OS and Xcode for the independent host. Isolate default Harmony packaging from the opt-in bridge and use offline packaging guards while the toolchain is paused. | Build/inspection checks do not claim runtime. Exact commit, platform and environment are visible; experimental libraries cannot be mistaken for the default HAR. |
| 2. Close the runtime matrix | Android: keep the API30 Maven-only gate, add a controlled successful HTTPS case paired with the untrusted case, and verify the declared API24 minimum on an authorized device/AVD. iOS: keep simulator and independent Swift/Kotlin consumer checks, inspect the final app's deployment target, and validate a signed arm64 host on a supported iPhone. Harmony: after clearance, build the default HAR, repeat double-HAR and API23 runtime checks and validate the intended minimum plus a supported physical device. | All claimed support points have direct evidence, including SDK/runtime version, device or simulator identity and the exact cases that ran. API18 compilation alone does not qualify as API18 runtime support. A subset run is reported as such. |
| 3. Freeze the public contract and release toolchain | Compare the evaluation pins with an upstream-supported build combination and rerun on the intended release configuration. Freeze stable public surfaces, verify binary/API baseline and upper-SDK dependency identity; document the public integration path, data bounds, thread/lifecycle contracts and supported OS/architectures. Align Android/iOS staging and the Harmony artifact plan without merging target-specific Maven repositories. | Fresh hosts compile, link and run from exact candidate artifacts with one Core per app, no producer checkout, no testkit or experimental dependencies, and named compatibility limits. |
| 4. Make distribution reproducible and reviewable | Inventory linked/copied runtime code and notices for each artifact. Resolve source license and upstream rights, immutable version and destinations, release artifact checksums and provenance. Keep Harmony publication closed while its tool/runtime rights are unresolved. | Reviewed component and license inventory, immutable candidate manifest, and approved license, destination and version. Separate preview and production coordinates. |
| 5. Release and maintain | Review the exact release candidate, then merge/publish only with separate authorization. Verify published hashes and fresh install; establish compatibility and maintenance policy. | Exact published versions and install/behavior results are traceable; release notes distinguish stable, preview and unsupported behavior. |

The common contracts, packaging checks and documentation can proceed in parallel
with environment and license evidence. Do not lower or raise a customer-facing
minimum to turn a red result green. Use a narrower, explicitly approved preview
scope if a release gate cannot be met, not an implicit production exception.

- **Harmony Kotlin storage:** ArkTS Preferences is host-owned; it is not a
  persistent Kotlin `StringStore`. A new cross-runtime storage adapter is a separate
  feature unless the planned release requires that promise.
- **Harmony Kotlin copied HTTP:** keep the bridge opt-in. A bounded C registry
  and Worker cleanup for queued work do not prove active RCP callback drain.
  Started calls retain `isDrained=false`; neither elapsed time nor Promise
  settlement is a native-drain guarantee.
- **Authorization:** no existing CI result, Draft PR or temporary artifact
  authorizes accepting new terms, launching paid infrastructure, uploading
  artifacts to a third party, merging or releasing.

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
