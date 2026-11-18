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
