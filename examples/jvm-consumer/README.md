# External JVM artifact consumer

The existing CI copies this entire directory outside the checkout and supplies
`-PmadcoreRepository=<staged Maven repository>` to the root Gradle wrapper.
Run `:run` as before. Core is resolved from Maven artifacts, never sibling source.

`upper-alpha` and `upper-beta` are independently compiled simulated upper SDKs.
Each has its own JAR task and depends on staged MadCore. The host consumes their
physical JAR outputs via file dependencies, not project dependency variants.
It explicitly declares MadCore, since bare JARs do not convey transitive Maven
metadata. These are thin JARs, not fat/shaded JARs.

`run` first verifies both JARs are on its runtime classpath, neither contains Core
classes, exactly one JAR supplies `StringStore`, and resolved Core module versions
agree. The host then checks that A's Core object passes through B by identity,
that their Core class objects are identical, and that A/B loaded from distinct
JAR files. Existing runtime-classpath auditing remains applicable.

This verifies simulated same-version JVM composition only. It does not establish
real product SDK compatibility, published upper-SDK Maven metadata, version-skew
resolution, isolated classloaders, Android/iOS/Harmony composition or licenses.
