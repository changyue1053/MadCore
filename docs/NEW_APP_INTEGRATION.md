# One SDK, multiple independent apps

MadCore's goal is a reusable foundation for NEW Android, iOS and HarmonyOS apps.
It is not a migration or API-parity project. Applications choose explicit host
adapters; SDK code must not know product IDs, backend endpoints, accounts or UI.

## Select the preview source and evidence

Use [Draft PR #1](https://github.com/changyue1053/MadCore/pull/1) to identify the
current candidate revision and its qualified evidence; do not assume `main` is
that preview. Before building, select a known full commit from the PR and check
`git rev-parse HEAD` against it in your evaluation checkout. Record that SHA with
your results. A newer commit does not inherit a previous commit's test outcome.

[DELIVERY_GATES](DELIVERY_GATES.md) separates historical CI, exact-head results and
local tests. In particular, the recorded e828305d iOS staging/independent-consumer
local run is not the complete iOS CI suite. Historical green run 44463243979 has
**zero downloadable artifacts** and is not evidence that the current head is
fully green. There is no SDK binary download/release attached to this handoff.
Private test HAPs are not release assets.

## Dependency choices and local preparation

- Android: consume `com.mad.core:madcore:0.1.0-SNAPSHOT` from the target-specific
  local Maven repository. From the reviewed checkout root, prepare it with:

  ```sh
  ./gradlew -Pmadcore.target=android assembleRelease publishAllPublicationsToStagingRepository
  ```

  Then point `-PmadcoreRepository` at the absolute path to
  `build/staging-repository/android`. A lone umbrella AAR is not the full Maven
  dependency closure. Do not combine different targets' staging directories.
  The [independent Android example](../examples/android-consumer/README.md)
  includes both upper AARs and the HTTP/TLS fixture for its existing runtime lane.
  Separate upper-Maven metadata/compile evidence and its no-runtime limit are
  recorded in [shared-Core integration](SHARED_CORE_INTEGRATION.md).

- iOS: `bash tools/build_ios_xcframework.sh` produces the evaluated device and
  arm64 Simulator MadCore XCFramework slices. Integrate the built framework and
  its privacy-manifest resource, not SDK source modules. For multiple Kotlin
  upper libraries, use one app-specific umbrella as in the
  [Kotlin composition example](../examples/ios-kotlin-composition/README.md);
  its local Core repository is `build/staging-repository/ios`.
  See [exact-head local evidence](DELIVERY_GATES.md#exact-head-local-ios-staging-consumer-evidence)
  and [toolchain compatibility limits](DELIVERY_GATES.md#tested-toolchain-versus-upstream-compatibility).
  These scoped checks are not App Store, signing/distribution or physical-device
  acceptance, and are not a promise that arbitrary Kotlin frameworks can coexist.

- Harmony: the HAR, native packaging and API23 simulator results are **historical
  evidence only**. **Do not execute Harmony/ohos/CLI/DevEco builds or bridge
  evaluation while SDK-license applicability review is pending.** This guide
  does not provide an active Harmony build step or authorize reusing private HAPs
  for distribution. API18 runtime, physical devices and redistribution remain
  open. See [Harmony evidence](HARMONY_RUNTIME_EVIDENCE.md) for the recorded scope.

- Test helpers are opt-in; do not add core-testkit to production by default.
- All coordinates and local outputs above are development evaluation artifacts,
  not publicly released package coordinates or permission to publish.

## Host-owned composition

Each app creates its own ConfigSnapshot, logger/sink, storage adapter, HTTP client
and ResourceScope. Do not introduce SDK-wide mutable application singletons.
App A and App B can use different endpoints, policies and storage namespaces
without SDK rebuilds. Construct requests in application/domain code; there is no
implicit auth, product identity header, retry or telemetry.

Choose a storage namespace that the host owns and can safely remove. Never use a
shared production preferences namespace for tests. Store secrets in a host-selected
secure store, not StringStore. Close only resources explicitly transferred to a
scope. A host-provided preference/session object does not become SDK-owned by
accident.

## Integration acceptance for every new app

1. Resolve packaged artifacts without importing the SDK source as an app module.
2. Confirm required platform permissions and privacy resources.
3. Run config, storage roundtrip, HTTP error/limits and resource-close smoke tests.
4. Keep Android/iOS blocking HTTP off the UI thread; Harmony RCP is async ArkTS.
5. Separate compile and runtime evidence: Harmony API18 compilation is distinct
   from the recorded API23 emulator run and is not a minimum-runtime promise.
6. Reject duplicate SDK classes in JVM dependency graphs. This protects new apps
   from conflicting dependencies; it is not an old-code compatibility check.
7. Review the public API status and platform-specific limits before release.

## Remaining platform work (Harmony evidence is historical while paused)

- Harmony API23 runtime covers native smoke, independent ArkTS RCP/Preferences
  and dual-HAR identity/shared mutation. Preferences restart checks are real, but
  the ArkTS adapter is not a persistent implementation of Kotlin StringStore.
- An opt-in copied Kotlin→RCP→Kotlin bridge is implemented and runtime-tested;
  default builds exclude it. Keep its owner-loop and bounded-capacity rules and
  `isDrained=false` limitation. Eight-slot recovery proves Promise admission quota
  reuse, not native resource drain.
- Worker teardown reclaimed four C sessions with queued, undispatched requests.
  This does not establish destruction safety during active RCP callbacks. See
  [experiment evidence](HARMONY_ASYNC_HTTP_EXPERIMENT.md); this is not permission
  to resume evaluation during the license pause.
- Build/release licensing and explicit publication approval remain open.
- API stability and broader method/cancellation needs should be driven by new-app
  use cases, not by matching a previous repository's surface area.

## Isolate reusable components' preferences

Wrap one host-owned StringStore with NamespacedStringStore for each component,
for example namespace `reader` and `editor`, both using logical key `theme`.
They address `reader.theme` and `editor.theme` independently. Reconstructing a
wrapper with the same namespace preserves the mapping. Namespace dots are forbidden
to avoid ambiguous boundaries. Logical keys are limited to95 characters.

Kotlin and ArkTS use the same mapping and validation rules. ArkTS hosts retain the
original PreferencesStringStore to explicitly await flush. This provides no access
control against other code that has the backend and does not share data between
separate OS application sandboxes.

## Deterministic application HTTP tests

Add the opt-in `core-testkit` artifact to the TEST configuration, not the production
umbrella. `ScriptedHttpTransport` queues HttpResponse or HttpFailure outcomes in
FIFO order, then injects into the normal HttpClient. Call assertExhausted() after
the application scenario to catch expected calls that never happened. An extra
call fails explicitly, not by silently returning an empty success.

The double retains no requests/URLs/headers, opens no sockets and performs no
sleep/retry. It is owner-thread only. callCount counts consumed outcomes, not
requests rejected by preflight. It does not verify route matching, TLS, OS
cancellation or asynchronous timing. Use separate integration tests for those.

## Check the development delivery graph

`SDK-MODULES.json` records the eight production components, the umbrella and the
opt-in testkit. JVM/Android publication jobs check the actual staged Maven POMs:
internal coordinates must resolve within staging at the declared version,
external runtime coordinates must be allowlisted, and no testkit dependency may
enter the production umbrella closure. Empty/missing publication sets fail.

The build generates `build/validation/publication-graph.json` with the observed
closure and POM SHA-256 values. This report contains no binaries or signing keys.
It is a development integrity check, not a published release, complete SBOM,
Gradle Module Metadata certification or licensing approval. Artifact-only consumer
builds remain necessary and are run separately. iOS/Harmony packaging keeps its
separate framework/HAR validation; this POM check does not replace it.

## Own cleanup explicitly in every app

Kotlin and ArkTS ResourceScope accept host-provided synchronous CloseableResource
objects. Registrations transfer cleanup ownership; detach returns that ownership
without closing. Close first marks the scope closed and detaches all entries,
then attempts LIFO cleanup. Duplicate registrations mean duplicate closes. A
rejected registration remains caller-owned. There is no automatic app lifecycle,
thread dispatch or asynchronous cancellation.

Hosts must serialize calls. Cleanup must not block indefinitely. Reports contain
only attempted/failed counts. Kotlin rethrows non-Exception Throwable after the
batch; ArkTS has no equivalent taxonomy and instead recognizes the explicit
FatalCleanupError marker. Ordinary ArkTS thrown values are counted/isolated. This
is a language difference, not a claim of identical runtime exception behavior.
The ArkTS facade does not retain Kotlin/native objects or bridge callbacks.
