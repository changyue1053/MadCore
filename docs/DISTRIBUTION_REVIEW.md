# Distribution review: unresolved, not legal clearance

Source publication and authorized cloud building do not by themselves establish
permission to release every binary component. No project license is selected by
this document. No new agreement is accepted.

| Gate | Evidence currently available | Needed before release |
| --- | --- | --- |
| Project source license | README states no license selected; no project LICENSE/NOTICE present; ten extracted files have provenance | Owner chooses intended downstream reuse terms and confirms rights to license all included source |
| Third-party notices | Gradle wrapper scripts contain Apache-2.0 headers | Inventory applicable licenses/notices and include required texts; do not replace upstream attribution |
| Pinned Huawei tools/SDK | Build pins CLI 5.1.0.840; recorded SDK 5.1.0.125/API18; build-use authorization exists | Review the recovered pinned archive notices and resolve tool-use scope separately from runtime redistribution |
| Native binary contents | HAR includes generated libmadcore.so and libmadcore_napi.so; libc++_shared.so is copied only into the temporary HAP consumer | Inventory compiler/runtime code actually linked/copied into each proposed release; map each component to pinned notices and redistribution terms |
| CPF runtime | Fork version 2.2.21-1.0.0; current upstream README lists Apache-2.0 and additional runtime components | Verify pinned artifact contents, including common-rt/Breakpad where present; current upstream prose is not a pinned inventory |

The license text from the exact pinned Huawei archive is not retained in this
checkout. Therefore this review makes **no version-specific permission or
prohibition assertion** about that SDK. The public source repository is not a
substitute for a complete binary license/notice inventory. `SDK-MODULES.json` and
the publication graph guard are dependency-boundary checks, not a legal SBOM.

Reference material (reviewed 2026-11-18):

- [GitHub repository licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [Apache License 2.0, redistribution section 4](https://www.apache.org/licenses/LICENSE-2.0)
- [Huawei C/C++ runtime integration guidance](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/c-cpp-overview-V5/) describes technical packaging, not blanket clearance.
- [CPF Kotlin upstream](https://gitcode.com/CPF-KMP-CMP/kotlin), current documentation only; pinned artifacts remain to be checked.

Until these items are resolved, keep the draft PR/evaluation workflow and do not
publish binary releases or claim production distribution approval. This review
identifies evidence gaps; it is not a legal opinion.

## Harmony release hold (read-only evidence)

The Linux CI lane used DevEco CLI `5.1.0.840` with reported SDK
`5.1.0.125`/API 18. The historical archive inspection verified the CLI ZIP
and retained the root LICENSE/NOTICE and OpenHarmony native notice evidence
in [run 44251615735](https://github.com/changyue1053/MadCore/actions/runs/44251615735/job/134623414953).
It does not resolve terms applicability. The separate
[API 23 simulator evidence](HARMONY_RUNTIME_EVIDENCE.md) used DevEco Studio
26.0.0 / SDK `26.0.0.105` and is not evidence for the Linux SDK, another
host runtime, or a minimum support floor.

- **Default HAR:** packages `libmadcore.so` and `libmadcore_napi.so` with
  ArkTS. It contains neither the experimental bridge nor `libc++_shared.so`.
  The native build uses CPF Kotlin/Native `2.2.21-1.0.0`; the NAPI build also
  uses the fork's `sysroot-ohos-aarch64-6.0.2.640-04`. The two project-built
  SOs still need a pinned inventory of any incorporated third-party objects.
- **Private test HAP:** adds AArch64 `libc++_shared.so` from
  `sdk/default/openharmony/native` in the pinned CLI. It is a host payload,
  not part of the default HAR. The historical Core ELF lists that runtime in
  `DT_NEEDED`; this does not identify statically linked runtime objects.
  See [historical packaging inventory](https://github.com/changyue1053/MadCore/actions/runs/44463243979/job/135354815561).

While the build and distribution hold stands, reconcile existing logs and
retained provenance only. Record the exact notices and their source entry
paths, then track three separate open questions: tool-use applicability to the
reusable Harmony output in this mixed-platform source tree; the exact host
runtime file-to-terms mapping under the referenced
[OpenHarmony SDK agreement](https://downloads.openharmony.cn/sdk/license/OpenHarmony-SDK.txt)
and native notice; and the linked CPF/compiler components and their matching
pinned notices. Mark missing artifacts, link maps or authorities as missing.
Do not infer clearance from a generic license, a missing archive entry, or a
historical build authorization.

## Build evidence collection

The native bridge build now writes `build/validation/harmony-native-inventory.json`:
SHA256, size, ELF machine, SONAME and DT_NEEDED of the two generated libraries.
This identifies dynamic dependencies, **not** statically incorporated Kotlin/CPF
runtime components or a license-complete SBOM. The inventory is printed in CI.

The existing authorized CLI build also writes
`build/validation/harmony-tool-terms-index.json`, a filename-keyword inventory of
license/notice/agreement files with hashes, without copying their text. CI prints
the first 100 matches and total count; the full temporary report is not published
as a release artifact. This does not accept any new terms. Keyword matching can
miss terms or include unrelated package licenses and proves no permission. Exact
relevant version-specific texts must still be reviewed before distribution.

### JVM and Android Maven evidence (local, optional)

Start from a newly staged repository for one target; do not combine target
directories. After the existing publication graph and independent consumer
checks, generate the review evidence locally:

```sh
mkdir -p build/validation
python3 tools/inventory_maven_release_evidence.py --target android build/staging-repository/android \
  > build/validation/android-maven-evidence.json
python3 tools/inventory_maven_release_evidence.py --target jvm build/staging-repository/jvm \
  > build/validation/jvm-maven-evidence.json
```

Retain the checkout commit and build invocation with each successful report;
an empty output after command failure is not evidence. The report separates:

- **Declared Maven evidence:** checked variant closures, POM SHA-256
  fingerprints and explicitly declared external Maven coordinates. Gradle module
  metadata files are hashed, not interpreted as a complete dependency graph or
  resolved classpath.
- **Observed packages:** exact JAR/AAR checksums, file sizes and classifiers,
  visible class namespace counts, listed embedded binary/archive member names,
  and one level of JARs inside AARs. This is an archive observation, not source
  or licensing attribution for bytecode, including relocated or embedded code.
- **Notice candidates:** filenames and hashes of apparent LICENSE, NOTICE and
  similar entries, without copying their contents. Names alone cannot prove
  terms apply; absence is not evidence a notice is unnecessary.

This does not resolve external artifacts, prove that all expected binaries
were built or that a publication is fully compatible/compliant, or cover iOS
KLIB/XCFrameworks and Harmony HARs. It does not change a license or publish an
artifact. Run the same evidence tooling against the final versioned artifact
set after its publication metadata and module manifest are aligned, and resolve
all open license decisions separately.

### iOS packaged evidence and private runner checks

Use the already built XCFramework from the exact source revision and Kotlin
version. This reads both device and simulator static archives and hashes
packaged files. It does not compile, sign or run an app.

```sh
umask 077
python3 tools/capture_ios_distribution_evidence.py \
  --xcframework madcore/build/XCFrameworks/release/MadCore.xcframework \
  --source-revision "$(git rev-parse HEAD)" --kotlin-version 2.2.21 \
  > build/validation/ios-packaged-evidence.json
```

Create the private destination directory before running this. If available,
add the exact cached supplier archive from the build and a matching independent
host executable and link map. A linker map only identifies loaded objects in
that particular host; it cannot account for unused material shipped in the
XCFramework. The supplier archive is broader than the packaged SDK and does
not prove which components were incorporated.

Regular validation uses its existing staged Maven outputs and XCFramework and
writes private ephemeral JSON in the runner temporary directory. CI prints
aggregate counts only and does not upload reports or binaries. To conduct an
attribution or NOTICE review, reproduce the capture on a controlled executor
where the matching files can be retained and inspected privately. Counts alone
are not the eventual release manifest or a permission decision.
