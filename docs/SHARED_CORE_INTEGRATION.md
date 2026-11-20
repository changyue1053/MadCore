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

The [Android API30 gate](../examples/android-consumer/README.md) publishes
two thin Android release components to local Maven, then removes their sources
and loose AARs. The host declares only Alpha and Beta, resolves transitively
against the staged Core Maven artifacts, and gates all four Debug/Release
compile/runtime classpaths and the seven real emulator cases. Exact-commit CI
determines whether this gate has passed. Historical API30 runs through
`da04570a684281a7afa1ca5e7359a337cc5e4389` used raw upper AARs and a direct Core
declaration, so they do not establish Maven-only runtime coverage.

## Android upper Maven publications: bounded local evidence

Recorded against exact source `e828305d121cf900502da708d448f33d7efcb645`, using
isolated temporary fixtures only. Existing Alpha and Beta sources were unchanged;
temporary Gradle configuration published their Android release components to a
disposable local Maven repository as `com.mad.probe:alpha:0.1.0` and
`com.mad.probe:beta:0.1.0`. Each retained its original `api` dependency on
`com.mad.core:madcore:0.1.0-SNAPSHOT`.

The independent app declared **only those two upper production coordinates**,
with neither a direct Core declaration nor local/raw AAR dependencies. The check
used the exact cached official AGP8.13.2 implementation via fixture-only
`pluginManagement.resolutionStrategy.useModule` because its plugin-marker
coordinate was absent offline. No version change, fabricated metadata or download
was used; this is not a change to the repository's build configuration.

Verified:
- Both release POMs preserve Core at compile scope; both API/runtime module
  variants preserve the transitive dependency and declare Android AAR elements.
  These upper module variants do not explicitly carry a Kotlin platform attribute.
- Debug and Release compile **and** runtime classpaths each select nine Core
  Android AAR implementations at one version, `0.1.0-SNAPSHOT`, with resolved
  `androidJvm` variants and no JVM fallback.
- The graph also contains root KMP metadata coordinates; those are not duplicate
  implementations. Each of the four artifact closures contains 66 unique Core
  classes with no duplicate definition. The two upper AARs contain no Core classes.
- Published upper AAR bytes match their release build outputs. An actual Java
  call constructing `SharedPreferencesStringStore` compiles in Debug and Release,
  exercising an Android-only adapter rather than accepting a JVM substitute.

This isolated run validates local publication metadata, dependency resolution and compilation,
**not execution through this Maven packaging route**. The earlier API30
identity/mutation runtime test uses raw upper AARs and explicit Core; it must not
be relabeled as this test. No API24/API36, physical-device, remote repository,
version-skew or binary-release claim follows. Private fixture logs and artifacts
are retained separately; nothing was uploaded or published externally.

Historical Harmony verification (tool execution is now paused for license review)
built two separate thin HARs against a normal Core dependency,
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
