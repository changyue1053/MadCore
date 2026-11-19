# Experimental Kotlin / RCP copied HTTP bridge

This opt-in slice connects a real Kotlin `AsyncHttpTransport` caller through one
C registry, an owner-loop NAPI/ArkTS pump, Huawei RCP, and copied results back to
Kotlin. It is not part of the default supported transport or a release claim.
Stable synchronous APIs are unchanged.

## Ownership and finite bounds

`-Pmadcore.copiedHttp=true` adds cinterop and the experimental Kotlin sources.
The C archive is embedded once in `libmadcore.so`; the additional NAPI facade
imports that registry, never compiles another copy. Link checks enforce this.
Only monotonically allocated value IDs cross runtimes. C holds no Kotlin object,
continuation or NAPI reference. A mutex fences lookup/copy/close. The environment
cleanup hook closes owned C sessions without calling Kotlin.

Four sessions, eight operations each; URL 2048 ASCII bytes, headers 16 KiB,
request/response body 64 KiB, timeout at most 120 seconds. GET/POST/PUT/DELETE,
request headers/body, status/response headers/body and policy are copied.
Malformed metadata fails closed. Default TLS trust and no-follow redirects remain
mandatory. Cleartext requires explicit request policy. Header JSON has bounded
strict UTF-8 decoding and rejects duplicates/malformed values.

ArkTS retains platform work separately. Its eight-outstanding-fetch quota is
released only when the actual fetch promise settles (or throws synchronously).
Cancel, timeout and close invalidate logical work and request platform cancellation;
they do not release this quota early or claim platform callbacks are drained.
A never-settling promise can exhaust capacity rather than permit unbounded work.
For every started transport call, **`isDrained` remains false**. This is an explicit
integration limitation for callers requiring proven quiescence.

## Reproduce without changing default source

1. Build the opt-in native library, then `bash tools/build_copied_http_bridge.sh`.
2. `MADCORE_COPIED_HTTP=1 bash tools/build_harmony_har.sh` compiles isolated HAR and
   consumer copies. The normal script remains default-only without this variable.
3. For an authorized device session, use the existing device runbook and controlled
   `tools/http_fixture.py --tls`. Supply loopback HTTP/TLS origins explicitly.
   Select **Run experimental Kotlin RCP bridge**. No public endpoint, trust bypass,
   credentials or background upload is used. Remove test reverse ports and stop
   the fixture afterward. Build scripts do not publish binary artifacts.

## Runtime evidence, 2026-11-19 UTC

An isolated Mac arm64 CPF 2.2.21-1.0.0 / Clang 19.1.4 /
sysroot 6.0.2.640-04 native build, packaged with existing DevEco SDK 26.0.0.105,
ran on a positively identified Pura 90 arm64 API 23 simulator. The final unsigned
private HAP SHA256 was
`21cf0aefa7eab8c3edcb7f37738b210bd0a7e64b22d6ab3873fb004aa497263a`.
The harness displayed `COPIED_RCP_KOTLIN_PASS`; ordinary native smoke also passed.

The eleven real request cases are GET body, POST header/body, PUT body, DELETE,
HTTP 400, response header copying, 302 no-follow, streamed response cap, timeout,
logical cancellation, and rejection of a self-signed TLS endpoint. Kotlin checks
returned status/body/headers. Fixture redirect hits remained zero; TLS handshake
attempts increased while TLS HTTP requests remained zero. Additional checks cover
eight-operation capacity, explicit close, synthetic late completion rejection,
new-session isolation and a fresh request after close.

Slow RCP work was initiated before cancellation/close; waiting afterward is **not**
evidence that its late callback arrived or native work drained. The fixture and
both test reverse ports were cleaned up. No binary or screenshot was published.

## Other checks and remaining gates

- C ASan/UBSan tests include bounded copy, races, close/cancel/late and ID exhaustion.
  LeakSanitizer is unavailable on the Mac host and explicitly disabled there.
- Exact ETS source with import-only host mocks covers success, malformed headers,
  synchronous fetch failure, cancellation/late/close, and never-settling quota.
- Kotlin codec JVM tests cover malformed UTF-8, escapes/surrogates, duplicate keys,
  controls and size limits. Native link checks verify one registry ownership.
- Official pinned API18 CI compilation is a separate gate, not implied by this
  SDK26/API23 device run. API18 runtime, physical devices, cross-environment teardown
  stress and proven transport drain remain unverified.
- Default platform CI and independent consumers remain required. Source readiness
  does not resolve third-party binary redistribution or project-license decisions.
