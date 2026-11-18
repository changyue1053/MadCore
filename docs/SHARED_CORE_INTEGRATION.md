# Several upper SDKs sharing one Core

The intended composition is one Core dependency, referenced by independently
built upper SDKs and the host. Do not embed a private copy of Core into each SDK.

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

Harmony builds two separate thin HARs against Core as a development dependency,
then deletes the upper projects before consuming their HARs plus one explicit
Core HAR in an unsigned HAP. A compiled page-level function passes the shared
NamespacedStringStore type from Alpha to Beta. Archive checks require exactly one
libmadcore.so/libmadcore_napi.so pair and no nested/native payloads in the upper
HARs. These are compile/package checks only: no Harmony runtime object identity,
loader behavior, persistence or transitive package publication is established.
Exact-commit CI determines whether these probes actually passed.
