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

Android currently tests a single artifact-only app, not two upper-SDK AARs.
Harmony currently tests a single independent HAR consumer and unsigned HAP; a
two-upper-HAR graph and device runtime are not verified. Keep those coverage gaps
explicit rather than treating JVM or Swift evidence as a three-platform result.
Exact-commit CI determines whether these probes actually passed.
