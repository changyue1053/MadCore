# Harmony simulator runtime evidence

Recorded 2026-11-19 UTC. This is one simulator evaluation, not a general support
or distribution declaration. No screenshots, binaries, credentials or user files
are included in this report.

## Exact scope

Source: `36856cf193d321aab49ec4ed9f6466d27a9592cc`; all 202 source blobs were
checked against their Git object hashes before building. Project source was
unchanged. Build outputs and exploratory host copies were isolated.

- Native: CPF Kotlin/Native `2.2.21-1.0.0`, Mac arm64 Clang `19.1.4`,
  native sysroot `6.0.2.640-04`, Java21, Gradle9.4.1.
- Host: installed DevEco Studio26.0.0 with SDK26.0.0.105. HAR and unsigned HAP
  compiled successfully. This is **not** the Linux CI CLI5.1/API18 toolchain.
- Target: DevEco arm64-v8a emulator, HarmonyOS6.1.0/API23. The test target was
  positively identified; another running emulator was not modified.
- The test application consumed the built Core HAR, not Core source modules.
  This session used one Core HAR, not the two-upper-HAR composition fixture.

A fixed compiler JAR download failed with an incomplete response. The exact
same-version existing local cached JAR was reused after checking its content
hash against the cache identity; the successful native build log is retained
privately. Generated C adapter and ArkTS warnings were not suppressed.

## Observed results

1. The unsigned evaluation HAP installed on this simulator without signing
   credentials. This is **not** evidence that unsigned packages work on physical
   devices or cloud debugging.
2. Real application UI reported `11 required native cases passed`, including
   the native ABI/time/bounded UTF-8 JSON smoke assertions.
3. Preferences preparation created/read/updated the test-owned value and awaited
   flush. The app was force-stopped; the old process disappeared, then a new
   process was launched without uninstalling or clearing data. The same token
   produced `STORAGE_RESTART_DEVICE_PASS`; only its test key was removed and
   flush acknowledged. This is restart persistence, not power-loss durability.
4. Real RCP calls produced `NETWORK_DEVICE_PASS` against a private loopback
   fixture through target-specific reverse forwarding. Assertions included
   preserved HTTP400, HTTP302 without following redirects, streamed body cap,
   timeout, untrusted self-signed TLS rejection and a later successful HTTP call.
   Independently observed fixture counters: redirect target hits **0**, accepted
   TLS connection attempts **1**, TLS application HTTP hits **0**. No trust store,
   certificate validation override or public endpoint was used.

Unsigned HAP SHA256:
`0270cb0cd5be4d7c8e2beeccb83819960698ad1f2c9e9788fc887a704d8f4475`.
The binary and screenshots remain private evaluation evidence, not release assets.

Only the two temporary forwarding rules were removed and the private fixture
stopped. The installed test app/simulator were retained for further scoped tests.

## What remains unproved

- API18 minimum runtime, other OS versions, physical devices and cloud devices.
- Two upper HARs sharing Core at runtime (existing CI establishes assembly only).
- Kotlin/ArkTS asynchronous HTTP/storage bridge: still NOT implemented. These
  checks call the independent public ArkTS wrappers and primitive C ABI.
- Cross-environment teardown, missing-callback drain, sustained memory stability,
  wider TLS matrix and public valid TLS behavior.
- License/notice clearance, stable release readiness or permission to merge.

## Finite next stage

First, make the existing two-upper-HAR fixture execute one explicit shared-store
identity/read-write assertion in the simulator host, without extending that
result to version skew or multiple embedded Kotlin runtimes.

For the real bridge, restrict the initial investigation to a single instance,
one owner event loop and one asynchronous primitive completion. Before binding
HTTP/storage, establish environment cleanup, native/Kotlin handle ownership,
callback dispatch and bounded shutdown/drain on the pinned runtime. Retain
failure-injection host tests and add simulator close/late-completion tests.
If accepted work cannot be safely drained after cancellation or teardown, stop
at that specific lifetime blocker rather than shipping a watchdog-only adapter.
Availability of a simulator does not itself resolve these ownership guarantees.

## Follow-up: two independent upper HARs, real execution

The same API23 simulator and SDK26 exploratory toolchain then ran the composition
probe added alongside this report. Core binaries remain from source
`36856cf193d321aab49ec4ed9f6466d27a9592cc`; only test-host generation changed.
The two upper HARs were built in independent projects against the Core artifact.
Both producer source directories were removed before the final application build.
The host consumed only alpha.har, beta.har and one explicit Core HAR.
Archive checks found thin upper HARs and exactly one Core native library pair.

The UI reported `DUAL_HAR_RUNTIME_PASS + native smoke`, including all 11 native
cases. The composition assertion checked returned-object identity (`===`),
`instanceof NamespacedStringStore` against the host's Core import, upper-SDK
mutation visible through both the shared object and its backend, host mutation,
and removal visible through both references. Repeated execution also passed.
The final factored test fixture was rebuilt, reinstalled and passed again.

Final private evaluation HAP SHA256:
`ec9cce1dd4371d3265b85dc2194be706a1b864d662429a8178c452a0656b49d5`.

This closes the narrow same-version two-upper-HAR runtime gap above. It does NOT
test transitive registry installation/version negotiation, multiple embedded
Kotlin runtimes, API18 runtime, or Kotlin/ArkTS async bridging. Network/storage
restart checks were not rerun for this composition-only update.

## Async bridge decision after runtime access

A worker-based native async adapter is not added in this stage. The installed
NAPI declarations specify that started work cannot be cancelled and work cannot
be deleted before completion. They do not establish completion ordering during
environment teardown. A timeout cannot authorize freeing live callback state.

The next candidate is an owner-loop-only, host-driven begin/complete token API:
ArkTS owns asynchronous activity and sends bounded primitive results back; native
code schedules no worker callback. Before retaining Kotlin continuations, this
still needs explicit per-instance ownership, reentrant-close and finalizer
ordering, Kotlin handle disposal/thread-entry proof, and late-result behavior
without raw native pointer reuse. The existing synchronous HttpTransport must not
be disguised as asynchronous. No production bridge claim follows from the current
simulator tests.
