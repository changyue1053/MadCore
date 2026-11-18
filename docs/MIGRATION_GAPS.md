# Extraction and migration gaps

Audit baseline: original repository revision
`6a2218cc6bef829ac38b2ca1046add25dc2e7dd0`, compared with MadCore's current branch.
This is a bounded audit, not certification of every original file or current main.

**MadCore is not a drop-in replacement for the original core tree.** Only the ten
files in SOURCE-PROVENANCE.json are pinned verbatim extractions. Other modules
contain newly designed standalone APIs. Similar module/package names do not imply
source, binary or behavior compatibility. Do not put both implementations on the
same classpath or link both native implementations into one app.

## Original 21 modules and current disposition

| Original area | MadCore status / gap |
| --- | --- |
| core-extension, core-time, core-json | Pinned source subset and tests; see provenance, not all-source parity |
| core-net | Redesigned bounded blocking GET/POST API; original is suspend send with Get/Post/Put/Delete/Patch, coroutine cancellation and request total timeout |
| core-config | New immutable local snapshot; original remote signed envelopes, refresh/cache, flags and settings are absent |
| core-storage | New non-secret string store; original quotas and low-space/media-write controls are absent |
| core-scope | Not extracted; ResourceScope only manages explicit close ownership, not account/app/host scopes or coroutine cancellation |
| core-obs | Not extracted; structured logging is not the original observation/diagnostic surface |
| core-testing | New opt-in testkit subset, not the original contract-test suite |
| core-account, core-auth | Not extracted; identities, credentials and authorization policy need separate scope |
| core-flags | Not extracted; no remote kill-switch or product rollout policy |
| core-platform, core-shellhost | Not extracted; original contracts include host/account/route and platform integrations |
| core-resilience | Not extracted; original startup ledger/safe-mode integration depends on host diagnostics |
| core-feature, core-design, core-i18n, core-router | Not extracted; product/UI composition is not silently added to the standalone foundation |
| core-upgrade | Explicitly deferred; not part of this Core foundation implementation |

## HTTP compatibility hazards

Original `com.mad.core.net.HttpTransport.send` is suspend; current `execute` is
blocking. Method enum names differ. Original response headers are single string
values; current lists preserve available multiplicity. Error types differ: TLS
rejection currently maps to sanitized Io rather than a separate TlsRejected type.
The current stronger no-redirect and defensive-copy policy does not supply the
original coroutine cancellation or end-to-end timeout guarantee. A trivial wrapper
would lie about cancellation/deadlines and must not be presented as compatible.
Original AuthorizedHttpClient's bearer refresh, identity headers and retry budget
were not moved. None are installed implicitly.

## Migration gate for later SDKs

1. Inventory the actual downstream imports and behavioral requirements.
2. Choose explicit API migration or a separately named compatibility adapter.
3. Add artifact-only consumer contract tests for cancellation, method/body/header
   behavior and errors before claiming old clients work.
4. Reject duplicate `com/mad/core` JVM classes in integration classpaths. This
   detects conflicts; it does not establish binary compatibility or cover native
   linking/Android DEX by itself.
5. Keep device/runtime and distribution-license gates separate from compilation.

Next low-risk work is test/contract coverage. Blindly copying every original core
module would import product policy and host coupling, defeating independent use.
