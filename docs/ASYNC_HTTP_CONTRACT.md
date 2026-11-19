# Asynchronous HTTP contract (source-level foundation)

`core-net` now contains a separate `AsyncHttpTransport`/`AsyncHttpCall` contract
and the adapter-side `AsyncHttpExchange` delivery cell. It does not change the
blocking `HttpTransport` API. There is **no platform async adapter** and no
Kotlin/ArkTS bridge in this change. Existing RCP remains an independent ArkTS API.

## Ownership and cancellation

Every operation belongs to one host-selected owner loop. The host serializes all
access, including property reads, completion, cancellation and drain attestation.
There is no lock, worker, callback, timer or scheduler supplied by this API.
Platform adapters must marshal events before accessing the cell.

`Pending -> Ready -> Consumed` is a single-consumer result transfer. Publication
and logical cancellation compete only in Pending. The winner is final; polling
once releases the cell's result reference. Cancellation has a sticky adapter-side
signal so consuming Cancelled does not erase the request to stop platform work.
Adapters must arrange observation of this signal; this cell does not wake them.
Do not spin-poll on a UI/event-loop thread.

Delivery and resource lifetime are separate. Consumed, Cancelled or Timeout does
not imply drained. Only an adapter with actual platform drain evidence may call
`markDrained`, after a terminal outcome. It is an attestation, not a mechanism to
stop work. If callbacks could still access native state, retain that state; never
use a watchdog expiry as permission to release it. A call can remain undrained.

`HttpRequest` and `HttpResponse` already copy payloads/header collections. The
cell retains at most one result and rejects oversized response bodies. This does
not bound an adapter's allocations, response headers, global number of calls or
network buffers. Those must be bounded separately before a real bridge is safe.
Response contents may be sensitive; only Failure's code is sanitized.

## Required adapter behavior, not yet platform-tested

- Prompt nonblocking start; no blocking wait on the owner loop.
- Reject insecure HTTP unless explicitly allowed, and oversized requests before I/O.
- Preserve HTTP error statuses; system TLS validation; no redirects or implicit retry.
- Enforce request/streamed-response limits and timeout semantics without unbounded buffering.
- Deliver copied data or sanitized failures exactly once; late platform results still
  require platform cleanup even when publication loses.
- Observe logical cancellation and request platform cancellation. Prove actual drain
  separately, including host/environment destruction.

## Tests and next integration gate

Common tests cover pending polling, single transfer, duplicate/late completion,
cancellation before/after completion, consumed cancellation signal, timeout versus
drain, premature drain rejection, body-cap rejection, copied data and independent
instances. These test the serialized cell, not networking, scheduling or NAPI.

Before a copied-result Harmony implementation, specify bounded wire encoding,
operation routing/instance generations, owner-loop pumping and cancellation
observation. Show a real Kotlin consumer receiving an RCP result, not only an
ArkTS Promise calling a C token registry. No retained Kotlin continuation should
be introduced without explicit disposal and teardown proof. Validate cancellation,
late results, close/recreate and malformed/oversized result paths on the simulator.

This is first-party source/API readiness for review, not release readiness or
third-party redistribution clearance. Project-license choice and native/toolchain
license/notice review remain independent gates; see DISTRIBUTION_REVIEW.md.
