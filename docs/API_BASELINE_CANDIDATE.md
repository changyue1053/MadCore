# Public API baseline candidate (not yet adopted)

This is an opt-in, local experiment for the production Kotlin modules and
`madcore` umbrella in `SDK-MODULES.json`. It inventories the existing public
surface, not a stability promise. If an unannotated public declaration should
remain experimental, decide its policy explicitly before adopting a baseline;
do not hide it with a broad name filter. The opt-in `core-testkit` and the
paused Harmony/CPF build are outside this probe. The existing official CI
lanes run self-checks with temporary compiler-generated references after
their independent consumer tests. The Android probe does not depend on the
separate API24 environment. No approved reference or release effect.

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

Run **Android and iOS separately**, in a fresh disposable copy for each lane;
don't overwrite or reuse the JVM candidate references. In an existing approved
runner, use the exact reviewed checkout to create the scratch copy. On exiting
the shell below, its builds, references and edits are removed. Do not enable
this for Harmony. The existing Android App and Swift/simulator gates are
independent from the candidate. To run the complete disposable probe
including the negative control on an already qualified host, use
`bash tools/test_abi_candidate.sh android` or
`bash tools/test_abi_candidate.sh ios`. The individual commands below
can also be used to inspect an unusual dump layout in scratch.

```bash
# Run from the reviewed checkout; choose android or ios before entering the shell.
lane=android
(
  set -euo pipefail
  case "$lane" in android|ios) ;; *) exit 2 ;; esac
  repo=$(git rev-parse --show-toplevel)
  revision=$(git -C "$repo" rev-parse HEAD)
  scratch=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-abi-$lane.XXXXXXXX")
  trap 'rm -rf -- "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git -C "$repo" archive "$revision" | tar -xf - -C "$scratch"
  cd "$scratch"
  printf 'MadCore ABI candidate: %s, %s\n' "$revision" "$lane"
  ./gradlew --version
  test ! -e "api-baseline/$lane"
  gradle=(./gradlew --no-daemon --console=plain "-Pmadcore.target=$lane" -Pmadcore.abiProbe=true)
  "${gradle[@]}" dumpLegacyAbi
  python3 tools/check_abi_candidate_inventory.py "$lane" actual
  test ! -e "core-testkit/build/api-baseline/$lane"
  "${gradle[@]}" updateLegacyAbi
  python3 tools/check_abi_candidate_inventory.py "$lane" reference
  "${gradle[@]}" checkLegacyAbi
  # For the lane-specific drift or Swift checks below, run here before exiting.
)
```

KGP **2.2.21** uses `dumpLegacyAbi`, `updateLegacyAbi` and `checkLegacyAbi`,
not the later task names. It uses JetBrains' version-matched `abi-tools` on its
check-only classpath, not an extra Gradle plugin or consumer runtime dependency.
Record the exact revision, toolchain, commands and individual outcomes. The
temporary reference only proves this compiler can freshly dump and compare
the same revision. It is not a baseline to commit or a compatibility promise.
Both inventory checks are required: KGP 2.2.21 walks the actual output files
and doesn't fail solely for an unmatched leftover reference.

- **Android:** Expect `android/<module>.api` and `jvm/<module>.api` per module.
  KGP supplies non-test Android compilation class directories; this can include
  both debug and release and is **not** the staged Maven AAR's public ABI.
  Record any overlapping-variant issue explicitly rather than ignoring a
  file, substituting the JVM view, or choosing one class arbitrarily. Keep the
  published-artifact and App runtime gates unchanged. Record SDK/AGP and no
  emulator is needed for this ABI probe.
- **iOS:** Expect `<module>.api` (JVM) plus `<module>.klib.api` whose root
  header lists exactly `iosArm64` and `iosSimulatorArm64`. The probe disables
  unsupported-target inference; fail if either real target is missing. Run
  only on the qualified macOS/Xcode toolchain and record those versions. JVM
  signatures and iOS Swift/Objective-C headers are not substitutes for KLIBs.

To verify lane-specific rejection, follow the [JVM negative control pattern](../tools/test_jvm_abi_candidate.sh)
inside that scratch shell with a public function in
`core-config/src/androidMain/kotlin/` on Android or
`core-config/src/iosSimulatorArm64Main/kotlin/` on iOS. Create just that
temporary file/directory if missing. After `:core-config:checkLegacyAbi` fails,
require the ABI-drift marker and fresh symbol in the Android dump or KLIB dump,
and its absence in the JVM dump. An unrelated compiler error is not a pass.
Remove the source, rerun the same check and inventory successfully, and check
that the symbol is gone. Don't update the candidate to accept the control.
A simulator-target control does not prove iOS device behavior.

## Swift and Harmony are separate surfaces

Kotlin/Native KLIB results do not describe the Swift-visible Objective-C facade.
Separately use the exact revision's release XCFramework from the existing
iOS packaging step, or build it in the qualified scratch copy. Check both
packaged slices and the same standalone Swift source, without simulator
startup, signing, or publication:

```bash
# Run in the scratch checkout; omit the build only if the identical artifact exists.
set -euo pipefail
xcodebuild -version
bash tools/build_ios_xcframework.sh
xc=madcore/build/XCFrameworks/release/MadCore.xcframework
for spec in ios-arm64:iphoneos:arm64-apple-ios15.0 \
            ios-arm64-simulator:iphonesimulator:arm64-apple-ios15.0-simulator; do
  IFS=: read -r slice sdk target <<< "$spec"
  header="$xc/$slice/MadCore.framework/Headers/MadCore.h"
  test -s "$header"
  shasum -a 256 "$header"
  xcrun --sdk "$sdk" swiftc -typecheck -target "$target" \
    -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" -F "$xc/$slice" \
    examples/ios-consumer/Consumer.swift
done
```

Review raw headers separately by slice alongside the exact toolchain. If you
have a previous authorized snapshot of the appropriate slice and toolchain,
use `diff -u` (no stripping attributes or selectors). Don't require device
and simulator headers to match each other. No header is stored in the repo
or distributed by this candidate. A typecheck checks the tested call sites,
not binary linking or runtime behavior; preserve existing App gates. Harmony
C exports and ArkTS API are unbaselined while Huawei tooling and distribution
are paused.
