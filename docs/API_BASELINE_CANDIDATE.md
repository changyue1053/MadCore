# Public API baseline candidate (not yet adopted)

This is an opt-in, local experiment for the production Kotlin modules and
`madcore` umbrella in `SDK-MODULES.json`. It inventories the existing public
surface, not a stability promise. If an unannotated public declaration should
remain experimental, decide its policy explicitly before adopting a baseline;
do not hide it with a broad name filter. The opt-in `core-testkit` and the
paused Harmony/CPF build are outside this probe. The existing JVM CI lane
runs a self-check with temporary, compiler-generated references after the
artifact-only consumer. Android, iOS and Harmony CI do not run this probe.
It has no approved reference or release effect.

The JVM self-check can also be run on a committed scratch revision with
`bash tools/test_jvm_abi_candidate.sh`. It archives HEAD into a disposable
directory, checks actual/reference inventories, requires the KGP comparison
to reject one deliberate public symbol, then verifies that removing the
symbol restores a passing comparison. It does not read otherwise-uncommitted
source or retain its reference dumps for later runs.

## Generate on the existing official-toolchain lanes

Use a fresh scratch checkout at the reviewed SHA, exact wrapper and pinned KGP.
JVM requires Gradle/JDK21, Android also its already-provisioned SDK and existing
AGP, iOS a compatible Mac/Xcode with both arm64 Kotlin/Native targets. Do not
install or accept a new SDK/toolchain solely to run this candidate without approval.

Run one lane at a time (repeat with `android` and `ios` where supported):

```sh
lane=jvm
./gradlew --no-daemon -Pmadcore.target="$lane" -Pmadcore.abiProbe=true dumpLegacyAbi
python3 tools/check_abi_candidate_inventory.py "$lane" actual
```

KGP **2.2.21** uses `dumpLegacyAbi`, `updateLegacyAbi` and `checkLegacyAbi`,
not the later task names. It uses JetBrains' version-matched `abi-tools` on its
check-only classpath, not an extra Gradle plugin or consumer runtime dependency.
Android records KGP's Android non-test class output (not a Maven/AAR inventory)
and a separate JVM dump; do not conflate the two. iOS requires a KLIB dump with
both `iosArm64` and `iosSimulatorArm64`; unsupported targets must fail, not infer
declarations. Linux/JVM results cannot stand in for either native slice.

In that scratch checkout only, after a human reviews the fresh dump files, stage
the candidate references, then run the comparison:

```sh
./gradlew --no-daemon -Pmadcore.target="$lane" -Pmadcore.abiProbe=true updateLegacyAbi
python3 tools/check_abi_candidate_inventory.py "$lane" reference
./gradlew --no-daemon -Pmadcore.target="$lane" -Pmadcore.abiProbe=true checkLegacyAbi
python3 tools/check_abi_candidate_inventory.py "$lane" actual
```

Actual dumps live at <module>/build/api-baseline/<lane>; reviewed references
live at api-baseline/<lane>/<module>. The JVM, Android and iOS lane directories
are intentionally separate. Run the host-only inventory tests with
`python3 tools/test_abi_candidate_inventory.py`.

Both inventory checks are required: KGP 2.2.21 compares files it actually
generates and does not fail solely because a reference file has no output.
The inventory check does not parse or compare API signatures; it guards against
missing lane/module outputs, empty files, extra dumps and incomplete iOS targets.
For a control, add a public top-level function to `core-config` only in the
scratch checkout and require `:core-config:checkLegacyAbi` to report ABI drift.
Remove that file, check again, and do not update the candidate to accept the
control change. A compiled ABI diff is not proof of source-level compatibility,
behavior, or the absence of experimental APIs.

## Swift and Harmony are separate surfaces

Kotlin/Native KLIB results do not describe the Swift-visible Objective-C facade.
On the existing authorized macOS lane, additionally build the release
XCFramework with `bash tools/build_ios_xcframework.sh`. Save and review each
slice's `MadCore.framework/Headers/MadCore.h` separately, as raw text with its
exact source and toolchain recorded. Compare later builds per slice using
`diff -u` and keep the existing external Swift typecheck. Do not strip attributes
or rename exported selectors during normalization. No Swift header reference is
included here. Harmony C exports and ArkTS API remain separate, unbaselined
surfaces while Huawei tooling and distribution are paused.
