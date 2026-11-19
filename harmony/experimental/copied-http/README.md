# Experimental copied HTTP mailbox

`copied_http.c` is one mutex-protected C object intended to be linked once into
libmadcore, not separately into NAPI. `copied_http.h` is the length-delimited ABI.
No Kotlin references or NAPI environments are stored. There are no platform
callbacks, background workers, raw-pointer identifiers or heap allocations.
Fixed storage is approximately 2.2 MiB for 4 sessions x 8 operation slots.

Session and operation IDs increase monotonically across close/consume/reopen and
fail at int32 exhaustion. No reset exists in the production API. Consume releases
a slot, so querying a consumed operation returns NOT_FOUND. Adapter-side dispatch
tracking must treat NOT_FOUND after previously dispatching an ID as invalidation,
not recreate it. Cancelled state remains sticky until consume/close. Any later
completion loses. This registry says nothing about actual cancellation or drain
of network work: a host must retain its own platform resources appropriately.

`next_request` copies the oldest queued GET request and its response cap. A
short output buffer does not dispatch it. Completion accepts only dispatched
operations, copies bounded bytes, and converts oversize to a terminal TOO_LARGE
failure without copying the body. Poll may inspect without consuming; a short
body buffer leaves the ready result intact. Close wipes all owned slots. Wiping
is ordinary memset, not a secure-erasure claim. This is a non-secret test bridge.

Transport policy remains a host obligation: this kernel validates basic ASCII
HTTP(S) shape and bounds, not ownership of endpoints, complete URL grammar, TLS,
redirects, header handling or request timeouts. There are no request/response
headers in this minimal GET-only ABI. C callers must provide valid stable buffers
and nonoverlapping output destinations for the duration of each call.

Run `bash harmony/experimental/copied-http/test_host.sh`. Strict warnings,
AddressSanitizer and UndefinedBehaviorSanitizer are enabled. LeakSanitizer is
explicitly disabled on macOS, where it is unsupported. Tests include copied data,
FIFO slot reuse, capacity, late completion, cancellation/close, malformed input,
size boundaries, concurrent cancel/complete winners and int32 exhaustion. Tests
include the implementation to inject near-exhaustion private counters; production
compiles it separately and exposes no such test control. These are host kernel
tests, not Harmony runtime, network or Kotlin lifetime evidence.

## Opt-in Kotlin/cinterop and link stage

Build with `-Pmadcore.target=ohos -Pmadcore.copiedHttp=true` and
`:madcore:linkReleaseSharedOhosArm64`. Default builds do not compile the additional
Kotlin source, cinterop or registry. The pinned compiler/sysroot is materialized
by core-time first; the C object is archived and embedded through core-net's
cinterop KLIB into the existing libmadcore.so. NAPI must link against that one
library, never compile a second registry. `check_copied_http_link.py` checks the
explicit exported definitions and absence of a circular NAPI dependency.
C archive/header changes are declared cinterop inputs to prevent stale embedding.

`CopiedGetMailbox` retains only integer IDs and transfers owned result bytes.
It is deliberately **not AsyncHttpTransport**: request headers/methods/timeouts,
response header encoding, host request pumping, NAPI environment ownership and
actual RCP work are not implemented. Missing/closed IDs fail explicitly. No
isDrained or platform cancellation guarantee is provided. Explicit close is
required in this component; automatic environment cleanup is a later gate.

### Actual component-only simulator evidence

On 2026-11-19 UTC, the opt-in source in this change was built using CPF2.2.21-1.0.0,
Mac arm64 Clang19.1.4 and sysroot6.0.2.640-04. An isolated SDK26.0.0.105 HAR/host
build used the test-only `probe_napi.c` adapter and a temporary ArkTS facade exposing
`copiedProbe()`. The existing consumer invoked it and required return value7
before its ordinary native smoke. This is a probe success sentinel, not a count
of seven independently named tests.

The positively identified Pura90 arm64/API23 simulator reported
`COPIED_MAILBOX_LINK_PASS (no network)` and all 11 existing native smoke cases.
A repeated UI invocation also passed. The Kotlin probe exercises request copy,
dispatch, response copy/HTTP400/body bytes, consumed-ID invalidation, cancellation,
late failure rejection and repeated close. This is real native/cinterop execution,
**not Kotlin→RCP→Kotlin delivery**, API18 runtime proof, teardown stress or HTTP support.

Private unsigned test HAP SHA256:
`fbac8740c84ac26da15327e2ca2944eb39ebf5d6bce27c908ecfe9efa86a07dd`.
No test binaries/screenshots or SDK files are published. Test source adapter is
not used by the default HAR. Compiler-generated adapter warnings were retained.

### Required next complete slice

Before actual transport integration, encode bounded request policy and response
headers, define owner-loop pump/cancellation observation and per-environment close.
Show a real Kotlin initiator whose value IDs route a controlled RCP response back
to Kotlin, plus cancel/late/close/reopen/capacity behavior. A discarded ID protects
C storage but does not establish RCP drain. No default supported API or release
claim should be made before this full path and licensing gates are resolved.
