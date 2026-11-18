# One SDK, multiple independent apps

MadCore's goal is a reusable foundation for NEW Android, iOS and HarmonyOS apps.
It is not a migration or API-parity project. Applications choose explicit host
adapters; SDK code must not know product IDs, backend endpoints, accounts or UI.

## Dependency choices

- Android: consume `com.mad.core:madcore:0.1.0-SNAPSHOT` from the local staging
  repository for development. The independent Android example demonstrates this
  without a project dependency or source checkout at the consumer location.
- iOS: integrate the built MadCore XCFramework and its privacy-manifest resource.
  The independent Swift/UIKit example demonstrates archive-only consumption.
- Harmony: integrate the built `madcore.har`; the standalone example consumes only
  that HAR. Host native-runtime requirements and device verification remain open.
- Test helpers are opt-in; do not add core-testkit to production by default.
- These are development artifacts, not publicly released package coordinates.

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
5. Treat compile-only platform results as compile-only, especially Harmony.
6. Reject duplicate SDK classes in JVM dependency graphs. This protects new apps
   from conflicting dependencies; it is not an old-code compatibility check.
7. Review the public API status and platform-specific limits before release.

## Remaining platform work

- Harmony native load, real RCP TLS/redirect/cancellation and persistent storage
  require a real runtime. Kotlin/ArkTS asynchronous object bridging remains a
  separately gated design, not an implemented feature.
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
