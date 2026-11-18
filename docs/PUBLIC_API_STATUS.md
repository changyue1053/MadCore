# Public API and verification status

MadCore is a pre-release standalone SDK, not a released compatibility promise.
The artifact group is `com.mad.core`, version `0.1.0-SNAPSHOT`. `madcore` is the
production umbrella; `core-testkit` is opt-in. No mad-repo checkout is required.

| Surface | Available interface | Verification boundary |
| --- | --- | --- |
| Kotlin foundation | extension, time, JSON, logging, config, lifecycle | Common tests; Android/iOS independent hosts; Harmony native compilation |
| Kotlin HTTP | HttpClient/HttpTransport, GET/POST/PUT/DELETE, bounded bytes, immutable copies | JVM and Android URLConnection; iOS NSURLSession; blocking, off UI thread |
| Kotlin storage | StringStore, memory, SharedPreferences, UserDefaults | Android/iOS adapter and native behavior tests; non-secret preferences |
| Harmony native | MadCore ABI version, epoch, bounded object-JSON predicate | C bridge host sanitizer tests + real native link/HAR compile, not device execution |
| Harmony HTTP | RcpHttpClient/RcpRequest/RcpResponse/RcpLimits | Async ArkTS, API18 compile + mocked policy/state tests, no device network proof |
| Harmony lifecycle | ResourceScope / CloseableResource | Exact-source host tests + API18 compile; host-serialized, no device proof |
| Harmony storage | PreferencesStringStore | Host-provided preferences; API18 compile + mocked tests, no persistence proof |

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

Exact commit CI is authoritative. Missing tests are not passes. Local self-signed
TLS rejection tests do not establish valid-public-certificate coverage, hostname
mismatch rejection, expiry/revocation handling or certificate pinning.
Harmony unsigned HAP assembly is not native load, networking or persistence proof.
Kotlin/ArkTS async bridging remains design-only: see CROSS_RUNTIME_BRIDGE.md.
Distribution licensing, runtime testing and explicit release/merge approval remain
separate gates. No toolchain SDK binaries or signing keys belong in this repository.

## HTTP methods

GET and DELETE accept no request body; POST and PUT accept bounded bytes, including
an empty body. DELETE here sends a request to the host-selected endpoint; the SDK
does not invent deletion policy or retry an operation. PATCH/HEAD and arbitrary
method strings are not exposed. Callers must handle uncertain outcomes after
timeout, especially writes. No retry is implied by method idempotence.

For the finite remaining delivery gates, see [DELIVERY_GATES.md](DELIVERY_GATES.md).
