# Public API and verification status

MadCore is a pre-release standalone SDK, not a released compatibility promise.
The artifact group is `com.mad.core`, version `0.1.0-SNAPSHOT`. `madcore` is the
production umbrella; `core-testkit` is opt-in. No mad-repo checkout is required.

| Surface | Available interface | Verification boundary |
| --- | --- | --- |
| Kotlin foundation | extension, time, JSON, logging, config, lifecycle | Common tests; Android/iOS independent hosts; Harmony native compilation |
| Kotlin HTTP | HttpClient/HttpTransport, GET/POST/PUT/DELETE, bounded bytes, immutable copies | JVM and Android URLConnection; iOS NSURLSession; blocking, off UI thread |
| Kotlin storage | StringStore, memory, SharedPreferences, UserDefaults | Android/iOS adapter and native behavior tests; non-secret preferences |
| Harmony native | MadCore ABI version, epoch, bounded object-JSON predicate | Host sanitizer/link checks plus scoped Pura90 arm64/API23 simulator native smoke; not API18 runtime or physical-device proof |
| Harmony HTTP | RcpHttpClient/RcpRequest/RcpResponse/RcpLimits | Independent ArkTS API; API18 compile/mocks plus controlled API23 RCP network, redirect/size/timeout and self-signed TLS rejection evidence |
| Harmony lifecycle | ResourceScope / CloseableResource | Exact-source host tests + historical API18 compile; host-serialized. Experimental Worker registry cleanup evidence is a distinct contract, not general lifecycle runtime coverage |
| Harmony storage | PreferencesStringStore | Host-owned ArkTS Preferences; API23 process-restart/read/remove proof, not power-loss durability or a common Kotlin StringStore persistence bridge |
| Experimental Harmony Kotlin HTTP | Opt-in bounded copied-result transport | Actual Kotlin→C→RCP→C→Kotlin API23 results and bounded lifetime tests; excluded from default builds, no in-flight native drain guarantee |

## Host responsibilities

- Choose explicitly which resources/adapters to instantiate. No global app,
  account, backend URL, auth, retry, telemetry or lifecycle wiring is installed.
- Keep blocking Kotlin HTTP off UI/event-loop threads. It has no caller-abort API.
  Limits are not a guarantee for DNS/write completion on every platform.
- Android host supplies INTERNET permission and intended network policy. Harmony
  host supplies INTERNET permission for RCP. System TLS validation is unchanged.
- Storage is not encrypted secrets storage, a database, transaction or crash
  durability guarantee. Serialize access where required by each adapter.
- ResourceScope is host-serialized; detach transfers ownership without cleanup.
  Registering the same resource twice means two close attempts.
- Swift/XCFramework hosts must include the packaged privacy manifest as a resource;
  wrapper reasons do not establish the host app's complete privacy declaration.

## Response headers

Kotlin HttpResponse exposes copied Map<String,List<String>> values. ArkTS
RcpResponse exposes copied Map<string,string[]> values. Keys retain the platform's
reported spelling; compare case-insensitively where appropriate. Arrays preserve
what the platform provides. Neither API promises original wire order or recovery
of duplicate fields already coalesced by the platform. Never split Set-Cookie or
quoted fields on commas. Headers may contain secrets; toString omits them.

## Evidence and release gates

CI results and separately recorded local runs apply only to their exact sources and tests. Missing tests are not passes. Local self-signed
TLS rejection tests do not establish valid-public-certificate coverage, hostname
mismatch rejection, expiry/revocation handling or certificate pinning.
Harmony unsigned HAP assembly alone is not runtime proof. Scoped native, RCP,
Preferences and dual-HAR simulator execution is recorded in
[Harmony runtime evidence](HARMONY_RUNTIME_EVIDENCE.md); later sections supersede
that report's initial stage-specific gaps. The real opt-in HTTP bridge is recorded
in [experimental HTTP evidence](HARMONY_ASYNC_HTTP_EXPERIMENT.md), not merely a design.
It remains experimental: started calls keep `isDrained=false`. Promise settlement
is not native callback drain; Worker cleanup covered queued, undispatched requests,
not active RCP teardown. Storage remains the independent ArkTS API.

Harmony API18 compilation and API23 simulator execution are separate evidence;
neither establishes API18 runtime or physical-device support. **Harmony tool
execution/builds are currently paused for SDK-license applicability review.**
Historical successful builds do not authorize resuming them or distributing binaries.
Distribution licensing, runtime testing and explicit release/merge approval remain
separate gates. No toolchain SDK binaries or signing keys belong in this repository.

## HTTP methods

GET and DELETE accept no request body; POST and PUT accept bounded bytes, including
an empty body. DELETE here sends a request to the host-selected endpoint; the SDK
does not invent deletion policy or retry an operation. PATCH/HEAD and arbitrary
method strings are not exposed. Callers must handle uncertain outcomes after
timeout, especially writes. No retry is implied by method idempotence.

For the finite remaining delivery gates, see [DELIVERY_GATES.md](DELIVERY_GATES.md).
