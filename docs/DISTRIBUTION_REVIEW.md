# Distribution review: unresolved, not legal clearance

Source publication and authorized cloud building do not by themselves establish
permission to release every binary component. No project license is selected by
this document. No new agreement is accepted.

| Gate | Evidence currently available | Needed before release |
| --- | --- | --- |
| Project source license | README states no license selected; no project LICENSE/NOTICE present; ten extracted files have provenance | Owner chooses intended downstream reuse terms and confirms rights to license all included source |
| Third-party notices | Gradle wrapper scripts contain Apache-2.0 headers | Inventory applicable licenses/notices and include required texts; do not replace upstream attribution |
| Pinned Huawei tools/SDK | Build pins CLI 5.1.0.840; recorded SDK 5.1.0.125/API18; build-use authorization exists | Recover exact version-specific bundled agreements/notices and distinguish tool use from redistributable runtime permissions |
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
