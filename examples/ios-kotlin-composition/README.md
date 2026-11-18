# App-specific iOS Kotlin composition probe

This probes a **single framework** containing two independently published Kotlin
upper-library KLIBs and one shared Core storage dependency. It does not load two
independent Kotlin frameworks together.

## CI invocation

From repository root on macOS with the existing Kotlin/Native prerequisites:

```sh
./gradlew --no-daemon -Pmadcore.target=ios :core-storage:publishAllPublicationsToStagingRepository
bash tools/test_ios_kotlin_composition.sh build "$PWD/build/staging-repository" "$RUNNER_TEMP/kotlin-composition"
# Boot an arm64 iOS Simulator and export MADCORE_IOS_SIMULATOR_UDID separately.
bash tools/test_ios_kotlin_composition.sh run "$RUNNER_TEMP/kotlin-composition"
```

Build mode does not require a booted simulator. It copies the producers outside
the checkout, builds/publishes separate `upper-alpha` and `upper-beta` artifacts
into a temporary Maven repository, deletes producer source, and builds a separate
umbrella project using only Maven coordinates. The umbrella exports both upper
APIs and Core storage once. A resolution guard requires each expected native
module exactly once. The independent Swift app then compiles using only the copied
`AppComposition.framework`; it never imports or links `MadCore.framework`.

Run mode installs the ad-hoc-signed simulator app, requires successful exit and
exactly one `MADCORE_KOTLIN_COMPOSITION_PASS` within 120 seconds, rejects its failure
marker, and terminates/uninstalls the test app on exit. Logs remain in the supplied
output directory. Swift checks Core object identity after crossing both upper
APIs, successful casts to the same exported MemoryStringStore type, and mutation
visible through the original reference.

Scope: simulated upper SDKs, Kotlin 2.2.21, core-storage, arm64 iOS Simulator only.
This is not original-product parity, independently distributed Kotlin framework
co-loading, version-skew compatibility, all-Core-module composition, device/release
signing, App Store privacy compliance or license clearance. The memory-only test
does not use UserDefaults. No production consumer packaging decision is implied.
