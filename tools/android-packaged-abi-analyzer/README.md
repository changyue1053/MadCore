# Local Android Release AAR ABI comparator

Both inputs are caller-supplied producer trees containing the exact nine
MadCore Release AARs in their normal module build output directories:

```sh
bash tools/compare_android_packaged_abi.sh /private/baseline /private/candidate
```

For a same-source toolchain rehearsal, build the Release AARs twice from
clean, separate trees of the **same pinned source revision**, with only the
audited toolchain configuration overlay differing. Record the source,
versions and build invocations independently. The comparator itself cannot
authenticate a source revision or the provenance of caller-supplied AARs.

In the current MadCore layout all eight production AARs and the umbrella
contain JVM classes (the umbrella's public entry point is `MadCoreInfo`).
The tool requires each expected Release AAR and inspects its packaged
`classes.jar` and all direct `libs/*.jar` files. A class must occur exactly
once in a producer closure, and its bytecode name must agree with its ZIP
entry. Missing packages, an unexpected JAR layout, symlinks, corrupt data,
duplicate or aliased class identities, and multi-release JAR classes are
not treated as a pass.

The separate analyzer uses JDK 21 and exactly
`org.jetbrains.kotlin:abi-tools:2.3.21` from Maven Central via the
repository's Gradle wrapper. Both sides are read by one Kotlin-aware
version of the analyzer, with empty API filters, without loading any app
class. Successful equal public binary signature dumps are required for all
nine AARs. This intentionally fails on any change, including a potentially
compatible addition, because the experiment holds source constant. Any
mismatch needs investigation, not a baseline rewrite.

Only fixed stages and numeric summaries are printed. Archive inputs,
private dumps and diagnostic logs stay in disposable local scratch and
are removed. The comparison is not ZIP equality, runtime/DEX/Android API
coverage, a source compatibility claim, or validation of manifests,
resources, consumer shrinker rules, consumer dependencies or outside
artifacts. There is no publish, emulator or Android SDK acquisition step.
