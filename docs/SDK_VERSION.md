# SDK version authority

The publisher reads `SDK-MODULES.json.version` for all Core publications.
The umbrella generates `MadCoreInfo.kt` from a checked-in template and the same
Gradle project version under its build directory. The template reproduces the
original source at the default version and declares no helper class or field. `MadCoreInfo.version` remains a public
`String` property. The default is still `0.1.0-SNAPSHOT`. This is not a
release-version decision.

The generator uses the official/fork-common Kotlin source-set API and declares
its version and template inputs and source-directory output. It does not read the manifest
at runtime, depend on a platform resource or modify tracked Kotlin sources.
The existing `66a4789c` immutable rehearsal remains locked to its historical
archive. Its prior results do not verify exported runtime version identity.

## Acceptance before relying on generated identity

- On the pinned official JVM runner, run
  `bash tools/test_sdk_version_generation.sh` from a committed checkout.
  The check uses a fresh local archive and a cold Gradle home, compares the
  public getter with two independent expected values, checks the JVM class
  inventory and public descriptors, verifies the exact default Kotlin bytes
  and published sources archive, and changes the input
  in place without cleaning the generator or compiler outputs. A new staging
  directory for each pass avoids mixing coordinates. No external publication.
- Also verify a clean direct source-publication path, Android release AAR/Maven
  publication, and iOS metadata publication and both XCFramework slices, with
  generated sources populated before compilation and source packaging.
  Compare ABI declarations before/after, including the AAR's `classes.jar`
  and iOS export headers, and verify no helper class, field or publicly visible
  Kotlin declaration appears. Verify incremental reuse with the same value
  and recompilation with a changed value. Keep runtime consumer expectations
  separately supplied when those lanes are later added.
- OHOS still consumes `commonMain` through its existing forked Kotlin target.
  There is no change to target selection, fork resolution or linker wiring.
  No OHOS build or rights review is attempted here.
