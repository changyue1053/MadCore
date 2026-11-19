# Several upper SDKs sharing one Core

The intended composition is one Core dependency, referenced by independently
built upper SDKs and the host. Do not embed a private copy of Core into each SDK.
Current baseline and remaining gates: [DELIVERY_GATES](DELIVERY_GATES.md).
Build evaluation artifacts from source/local staging; green CI has no downloadable
SDK artifacts and does not constitute package publication.

## Artifact-level probes

- JVM: two thin upper-SDK JARs and an independent host resolve the published Core
  artifacts; the classpath guard rejects overlapping Core class definitions.
- iOS: FeatureAlpha and FeatureBeta are independently compiled Swift static
  archives/module interfaces referencing one MadCore XCFramework slice. The
  source copies are deleted before compiling the UIKit host. The host passes a
  ConfigSnapshot through Beta to Alpha, checks object identity and reads its
  typed value, then completes the existing runtime checks.

The iOS probe checks thin Swift SDK composition. It does **not** establish that
multiple independently produced Kotlin/Native frameworks can each re-export or
statically bundle Core/Kotlin runtime without duplicate types or symbols. That
layout needs a separate export/link strategy and test; do not infer it from this
probe. Current artifacts are same-toolchain evaluation builds, not Swift ABI
stability or cross-version compatibility promises.

Android additionally builds Alpha/Beta in an outside-checkout library project,
then copies their AARs to the independent app and deletes the upper SDK build
project. The host explicitly resolves Core from staged Maven; local AAR files do
not carry transitive dependency metadata. The emulator test passes a StringStore
between the AARs and checks instance/type identity. Archive guards reject embedded
Core classes/native libraries. This is not published upper-AAR metadata validation.

Harmony builds two separate thin HARs against a normal Core dependency,
using a project-level override to the local built Core HAR, then deletes the upper projects before consuming their HARs plus one explicit
Core HAR in an unsigned HAP. A compiled page-level function passes the shared
NamespacedStringStore type from Alpha to Beta. Archive checks require exactly one
libmadcore.so/libmadcore_napi.so pair and no nested/native payloads in the upper
HARs. In addition to compile/package checks, the separate recorded Pura90/API23
runtime probe invoked the composition helper and passed object/type identity,
cross-upper mutation and removal with one Core. This does not prove API18 runtime,
physical devices, arbitrary loader/version combinations or remote package metadata.
The final project override resolves both upper dependencies to its one local Core
HAR. Preferences persistence is a separate ArkTS runtime test, not evidence that
the two upper HARs implement Kotlin persistent storage. See
[runtime evidence](HARMONY_RUNTIME_EVIDENCE.md).
Exact-commit CI determines whether these probes actually passed.

The override mechanism follows [Huawei OHPM documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/ide-oh-package-json5-V5/). Development-only dependencies are not used for imported runtime Core types.

## Kotlin upper libraries through one iOS umbrella

A separate `examples/ios-kotlin-composition` probe publishes two independent
Kotlin upper KLIBs against published Core storage, removes their sources, and
builds an app-specific umbrella from Maven coordinates. A Swift simulator host
imports only that one framework and checks shared object identity, concrete type
casts and cross-upper mutation. This is distinct from the thin Swift archive
probe above; it does not approve co-loading separate Kotlin frameworks or mixing
versions. Only Core storage and arm64 Simulator are covered by this probe.

The architecture follows [Kotlin's multi-module configuration guidance](https://kotlinlang.org/docs/multiplatform/multiplatform-project-configuration.html).
Exact-commit CI still determines whether build and execution passed.

## Experimental bridge is a separate opt-in surface

The real copied Kotlin/RCP bridge and queued-Worker teardown tests do not enlarge
the default shared-Core composition claim. They validate bounded copied delivery,
ID isolation, Promise quota recovery and network-free Worker C-registry cleanup
in the recorded API23 setup. They do not prove active RCP teardown/native drain or
a Kotlin-to-Preferences persistent adapter. No experimental native library should
be silently included in a default preview artifact. See
[async experiment](HARMONY_ASYNC_HTTP_EXPERIMENT.md).
