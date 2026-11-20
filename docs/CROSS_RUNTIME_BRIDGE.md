# Cross-runtime bridge contract (design, not implemented)

The current primitive C ABI owns no ArkTS/Kotlin objects across calls. RCP and
Preferences are independent ArkTS facades; they do not implement Kotlin
HttpTransport or StringStore. This document is a gate for future bridge work,
not a supported bridge API.

## Required ownership and threading decisions

- Each bridge belongs to one host-created instance and one ArkTS environment.
  Never retain a process-global napi_env or borrow handles across environments.
- All NAPI calls occur on the owning event-loop thread. Kotlin's blocking HTTP
  interface must NOT synchronously wait on that thread for an ArkTS Promise.
  Prefer a separately named asynchronous port instead of disguising blocking
  behavior. Existing Android/iOS blocking APIs must remain explicit.
- Each in-flight operation owns a bounded request snapshot, opaque generation
  token and exactly one completion. No pointers or credentials in public IDs.
- Completion, timeout, cancellation and environment shutdown race through one
  terminal-state transition. Late results are discarded without touching a
  released environment. Cleanup occurs on the owner thread.
- Reference creation/deletion and Kotlin StableRef disposal must balance on
  success, callback throw, enqueue failure, cancellation and host destruction.
  No direct exception propagation across the C ABI. Return sanitized error codes.
- Host close stops new work, cancels pending work and drains/releases references.
  Repeated close is safe. Do not close host-owned global preferences or sessions.
- StringStore is synchronous today; an asynchronous persistence bridge needs a
  distinct API. Preferences flush acknowledgement is not crash durability.

## Required evidence before support

1. Pure state-machine tests including repeated/late completion and shutdown.
2. Native error-injection tests for allocation and reference/queue failures.
3. Real Harmony device tests for event-loop responsiveness, cancellation,
   repeated create/close, memory growth and library loading.
4. Actual network tests: redirect target hit count zero, bad TLS certificates
   rejected with system trust unchanged, streaming caps and timeout cleanup.
5. Storage create/read/update/remove/flush plus process-restart checks in an
   isolated host-owned namespace. No reading unrelated application data.
6. Artifact-only host integration; no mad-repo product or build dependency.

No unreviewed new toolchain/image license or signing material belongs in this
repository. Missing device evidence remains a release blocker.

## Experimental contract evidence

`harmony/experimental/async-contract` now contains a fixed-capacity owner-thread
operation registry with host ASan/UBSan tests. It establishes only token ownership
and terminal-state behavior under serialized event orderings. It is excluded from
production exports and HAR. No NAPI references, Kotlin handles, async callback
queue or cross-runtime request path is implemented by this experiment.

## Real async integration stop gate

The abstract adapter must not be swapped for NAPI calls based on compilation
alone. Before doing so, establish all of the following for the pinned headers and
runtime: per-environment teardown callback ordering; owner-loop completion
marshalling; Kotlin thread-entry and lifetime rules; and a shutdown protocol that
never frees callback state while an accepted platform operation may still call
back. A watchdog can settle a public operation, but does not prove underlying
work has stopped or permit freeing its callback pointer. A missing callback can
otherwise force a choice between a leak and use-after-free. Neither is acceptable.

Current host tests exercise logical ownership, not these runtime guarantees.
Therefore the experimental adapter remains unbound to NAPI and excluded from
production, rather than presenting an unsafe pseudo-implementation as progress.
