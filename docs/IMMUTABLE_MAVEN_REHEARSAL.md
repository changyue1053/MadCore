# Local immutable Maven rehearsal (not a release)

The checked-in default remains 0.1.0-SNAPSHOT; no immutable release version
or publication destination is selected. This is a JVM/Android rehearsal
against Draft 66a4789c. iOS KLIB staging, its exact input checks and real device
testing are out of scope. Do not use Huawei tools or merge these stages
into a unified multiplatform Maven repository.

Supply an explicit, disposable X.Y.Z-rehearsal.N token. Ordinary versions,
dynamic selectors and snapshots are rejected. From a checkout that already
contains the exact pinned revision, run one lane at a time:

    bash tools/rehearse_immutable_maven.sh jvm "$token" --prepare-only
    bash tools/rehearse_immutable_maven.sh jvm "$token"
    bash tools/rehearse_immutable_maven.sh android "$token"

Preparation-only checks source hashes and the scratch overlay, with no Gradle
invocation. Full rehearsal uses the pinned wrapper/JDK21 and already installed
Android SDK 36/build tools. System SDK acquisition and device execution are
disabled. Standard pinned plugin and Gradle dependency downloads may occur
on an approved build executor.

The helper archives the pinned source into isolation, rewrites only matching
local scratch files, and stages in per-lane file repositories. MadCore
coordinates resolve exclusively from the designated stage. Android continues
to declare only two published upper AARs at their independent fixture version;
the build checks four classpaths and assembles APKs without running them.
JVM retains its artifact-only Core consumer and separate thin upper JARs.

The independent expected Core version is checked against the manifest, POM
graph, Gradle metadata, target references, and advertised artifact hashes.
Artifact-directory Maven metadata is allowed; version-directory metadata is
not. Scratch files are discarded. There is no external publication, stable
version adoption, or proof of reproducible bytes across independent builds.
