# Optional same-source Android packaged ABI rehearsal

Requires the separate packaged ABI comparator, a Git checkout containing
`9555b58b3af91165e4a1a2a8db02ba3c1903c24a`, a Linux x86_64 build runner with
a full local JDK 21, Android SDK 36 and Build Tools 35.0.0 already provisioned,
and access to the project's normal Gradle and Maven tool/dependency origins.
It does not need KVM, an AVD, an Android device, an SDK download, or a remote
package repository.

```sh
bash tools/rehearse_android_packaged_abi.sh
```

The runner hashes the exact archived toolchain overlay and wrapper declaration,
then prepares two disposable copies of the same source. Both build Release
AARs only. The baseline remains Kotlin 2.2.21/Gradle 9.4.1; the official overlay
uses Kotlin 2.3.21/Gradle 9.3.0; AGP 8.13.2 and platform versions are unchanged.
The archived baseline wrapper gets the official 9.4.1 ZIP checksum in scratch.
The producer caches are separate. Android SDK and JDK auto-acquisition are off.

A scratch copy of the comparator's analyzer first compiles three toy Java
fixtures with the actual JDK. It requires a proven classfile body change with
equal signatures, a public return descriptor drift it can actually see, and
correct public, protected and private visibility handling. It then compares the
nine packaged AARs using that same 2.3.21 analyzer, independent of the producer
compiler or Kotlin task variant labels. The fixture never enters product
source or an AAR. This control does not validate general Kotlin metadata drift,
shipping runtime behavior or binary reproducibility.

The sole normal outputs are fixed progress markers and numeric ABI summaries.
Work trees, fixtures, archives, compiler output and raw analyzer dumps stay
local to the invocation and are cleaned on exit. No report upload or publishing
is performed. A tooling, archive, or metadata failure remains a failure, not
an ABI incompatibility claim. A real nonzero ABI delta is a review signal, not
permission to silently adopt the new toolchain.

## Optional one-transition Draft CI

Do not activate automatically. If authorized to trial on the same-repository
Draft PR, use a dedicated `pull_request` workflow with `contents: read`;
guard repository `changyue1053/MadCore`, PR number 1, draft status, exact same
head repository and `work/core-validation-testkit` head branch. Check out the
event's exact head SHA with credentials persistence off and enough history to
contain the pinned archive. Before JDK setup or rehearsal, require the one
reviewed direct-parent SHA and an exact ordered add-only list from
`git diff --no-renames --name-status`; reject other changes. Skip later
parent transitions. For a lane added after the comparator and the runner
land, allow only its own workflow addition in that transition.

Use the existing pinned checkout and JDK-setup actions, `ubuntu-latest`,
JDK 21, a scoped timeout (up to 40 minutes), read-only CI permissions, and no
artifact upload, signing, release, Android device steps or SDK acquisitions.
Run the synthetic Python gate first, then invoke only the local rehearsal.
Do not change default validation, API24, iOS, or Harmony on activation.
