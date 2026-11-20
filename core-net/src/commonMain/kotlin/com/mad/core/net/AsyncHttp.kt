package com.mad.core.net

/** Single-consumer delivery state, independent of whether native/platform work has drained. */
enum class AsyncHttpState { Pending, Ready, Consumed }

/** Owned result; failures contain only a code, never platform exceptions or request diagnostics.
 * Response headers/body may contain sensitive application data; callers must not log them blindly. */
sealed class AsyncHttpResult {
    class Response(val response: HttpResponse) : AsyncHttpResult()
    class Failure(val failure: HttpFailure) : AsyncHttpResult()
    object Cancelled : AsyncHttpResult()
}

/**
 * Owner-loop-only, nonblocking operation. Host serializes EVERY method/property access.
 * No method schedules work or waits. poll() transfers the sole result once; null means
 * Pending or Consumed (inspect state). Cancellation wins only while Pending and makes
 * Cancelled ready immediately. It is logical cancellation, NOT platform drain evidence.
 *
 * isDrained becomes true only after the adapter proves no future platform callback can
 * touch operation resources. A consumed/cancelled call may remain undrained indefinitely.
 * Keep adapter-owned resources alive until actual drain; a timeout cannot authorize free.
 * Result ownership transfers to the caller on poll; retaining the result is its choice.
 */
interface AsyncHttpCall {
    val state: AsyncHttpState
    val isDrained: Boolean
    fun poll(): AsyncHttpResult?
    fun cancel(): Boolean
}

/**
 * Separate from blocking HttpTransport; no platform implementation is supplied here.
 * start returns promptly and performs no blocking network work on the owner loop. Adapters enforce
 * HttpLimits, system TLS, no redirect following and bounded streaming, with no implicit
 * retries/auth. Request/response snapshots are owned copies, never borrowed pointers.
 * All delivery and cancellation transitions occur on the same host-selected owner loop.
 * An adapter must observe logical cancellation and request platform cancellation, but
 * may mark drain only on a documented platform guarantee. Do not spin-poll on the UI loop.
 *
 * Adapters MUST reject disallowed cleartext and bodies over maxRequestBytes before I/O.
 * Invalid requests/policy failures MUST return a ready Failure and a drained call,
 * without starting I/O. Unexpected programming failures may throw before ownership moves.
 */
interface AsyncHttpTransport {
    fun start(request: HttpRequest, limits: HttpLimits): AsyncHttpCall
}

/**
 * Adapter-side delivery cell/reference state machine, NOT an HTTP adapter or NAPI bridge.
 * Fixed one-result capacity; no timer, worker, callback, cross-runtime reference or lock.
 * The adapter retains this object and exposes only call to its consumer. All methods,
 * including markDrained, MUST be serialized on the owning loop by the adapter.
 *
 * publish rejects late/duplicate results without taking ownership. The adapter releases
 * its own platform resources even when publication loses. HttpResponse already copies
 * body/headers; maxResponseBytes caps retained body, not platform allocation or headers.
 */
class AsyncHttpExchange(private val limits: HttpLimits = HttpLimits()) {
    private var deliveryState = AsyncHttpState.Pending
    private var result: AsyncHttpResult? = null
    private var drained = false
    /** Sticky adapter-visible cancellation signal, including after consumer poll(). */
    var isCancellationRequested: Boolean = false
        private set

    val call: AsyncHttpCall = object : AsyncHttpCall {
        override val state: AsyncHttpState get() = deliveryState
        override val isDrained: Boolean get() = drained
        override fun poll(): AsyncHttpResult? {
            if (deliveryState != AsyncHttpState.Ready) return null
            val owned = result
            result = null
            deliveryState = AsyncHttpState.Consumed
            return owned
        }
        override fun cancel(): Boolean = publish(AsyncHttpResult.Cancelled)
    }

    fun publish(value: AsyncHttpResult): Boolean {
        if (deliveryState != AsyncHttpState.Pending) return false
        if (value === AsyncHttpResult.Cancelled) isCancellationRequested = true
        result = if (value is AsyncHttpResult.Response && value.response.bodySize > limits.maxResponseBytes) {
            AsyncHttpResult.Failure(HttpFailure.ResponseTooLarge)
        } else value
        deliveryState = AsyncHttpState.Ready
        return true
    }

    /** Adapter attestation, not a cancellation primitive. Requires a terminal delivery outcome. */
    fun markDrained() {
        check(deliveryState != AsyncHttpState.Pending) { "Outcome required before drain" }
        drained = true
    }
}
