# Experimental async ownership kernel (not shipped)

This is the first bounded contract slice, not an asynchronous bridge or public API.
It is deliberately excluded from C ABI exports, HAR and Kotlin modules. No
network/storage request crosses runtimes through it.

A fixed 16-slot owner-thread registry issues monotonic nonzero tokens, rejects
capacity/closed/exhaustion without taking ownership, and lets exactly one terminal
transition detach a token. Close detaches every remaining token before caller
cleanup, so late completion cannot reacquire it. Token exhaustion fails closed;
there is no wraparound alias. A registry must never be reset/reused while callbacks
from its old lifetime can still arrive. Different environments require different
registries and a future routing layer; numeric tokens alone are not sufficient.

Host sanitizer tests cover capacity, slot reuse/stale tokens, duplicate finish,
close at every position among terminal contenders, repeat close, and exhaustion.
These are serialized state-machine tests, not concurrent-thread tests. Current
code does not retain or dispose references, allocate payload buffers, schedule a
callback, cancel platform work, or implement a timeout clock.

## Next integration gates

- Introduce a separately named async port; never block ArkTS on Kotlin HTTP.
- Define per-environment ownership and bounded snapshots, then map token owners
  to NAPI references and Kotlin lifetime handles with error-injected cleanup.
- Marshal completion to the owning event loop and drain safely on teardown.
- Compile against the pinned NAPI headers and run real device memory/thread,
  cancellation and late-result tests before claiming support.

Until those gates pass, use the independent ArkTS RCP/Preferences APIs. The
experiment does not change production behavior or remove any delivery blocker.

## Abstract reference/dispatch slice

`reference_dispatch.h` layers a caller-supplied retain/release/enqueue/complete
adapter over tokens. Host fakes allocate real heap references under sanitizers.
Tests inject retain failure, queue rejection, callback failure, capacity rejection,
duplicate terminal delivery and callback-triggered reentrant close. Successful
retains are balanced; ownership detaches before callbacks. Close releases pending
references without invoking user callbacks.

This is still not a NAPI adapter: the scheduler contract requires no inline
completion and no retained work after enqueue failure. Release must not reenter.
A real scheduler must stop/drain before the dispatcher is destroyed; ignoring
late tokens while the dispatcher lives does NOT prevent use-after-free after it
is freed. These conditions are integration obligations, not verified platform
behavior. There is no cross-thread access, payload transfer or Kotlin StableRef.

Accepted enqueue with a permanently missing completion is tested through explicit
host-timeout termination and close; a late result must lose. The kernel has no
clock and never interprets enqueue success as completion. No platform guarantee
about `napi_queue_async_work` or cancellation is assumed. Real adapters need an
independent owner-thread watchdog and a safe scheduler drain strategy, including
callbacks that never arrive. Active callbacks must not destroy/reinitialize the
dispatcher; its lifetime extends until all calls and scheduler references drain.
