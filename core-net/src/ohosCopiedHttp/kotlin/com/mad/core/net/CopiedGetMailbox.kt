@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core.net

import com.mad.core.net.copied.*
import kotlinx.cinterop.*

/** Experimental GET mailbox, NOT AsyncHttpTransport: no network driver/header/timeout protocol yet.
 * C owns fixed-capacity state. Kotlin retains only value IDs; no C pointer or callback is retained.
 * All public caller access is owner-loop serialized; C also fences lookup/close with its mutex.
 */
class CopiedGetMailbox private constructor(val sessionId: Int) {
    companion object {
        fun open(): CopiedGetMailbox {
            val id = mc_http_open()
            check(id > 0) { "Copied mailbox unavailable" }
            return CopiedGetMailbox(id)
        }
    }
    fun begin(url: String, maxResponseBytes: Int): Int {
        require(url.length in 1..2048)
        val bytes = url.encodeToByteArray()
        require(bytes.size in 1..2048 && maxResponseBytes in 1..65536)
        return bytes.usePinned { mc_http_begin(sessionId, it.addressOf(0).reinterpret(), bytes.size, maxResponseBytes) }
    }
    fun cancel(operationId: Int): Boolean = mc_http_cancel(sessionId, operationId) == 1
    fun close() { mc_http_close(sessionId) }

    /** null pending; missing/closed IDs are explicit errors, never stale pointer access. */
    fun take(operationId: Int): CopiedGetResult? = memScoped {
        val state = alloc<IntVar>(); val status = alloc<IntVar>(); val error = alloc<IntVar>(); val length = alloc<IntVar>()
        var bytes = byteArrayOf()
        // Empty/pending results need no payload allocation. A nonempty result remains
        // unconsumed when capacity is too small; retry under C's lookup/close fence.
        var code = mc_http_poll(sessionId, operationId, state.ptr, status.ptr, error.ptr,
            null, 0, length.ptr, 1)
        if (code == MC_HTTP_BUFFER_TOO_SMALL) {
            check(length.value in 1..65536) { "Copied mailbox invalid size" }
            bytes = ByteArray(length.value)
            code = bytes.usePinned {
                mc_http_poll(sessionId, operationId, state.ptr, status.ptr, error.ptr,
                    it.addressOf(0).reinterpret(), bytes.size, length.ptr, 1)
            }
        }
        check(code >= 0) { "Copied mailbox result unavailable" }
        if (code == 0) null else CopiedGetResult(state.value, status.value, error.value, bytes)

    }
}

/** Owned snapshot. Numeric experimental state/error values follow copied_http.h, not stable wire ABI. */
class CopiedGetResult(val state: Int, val status: Int, val error: Int, body: ByteArray) {
    private val bytes = body.copyOf()
    val body: ByteArray get() = bytes.copyOf()
}

/** Native link/runtime probe only. Uses in-memory completion, NOT RCP or a device network test. */
fun copiedHttpLinkProbe(): Int = memScoped {
    val session = CopiedGetMailbox.open()
    try {
        val id = session.begin("https://example.invalid/", 3)
        check(id > 0 && session.take(id) == null)
        val outId = alloc<IntVar>(); val length = alloc<IntVar>(); val limit = alloc<IntVar>()
        val url = ByteArray(2048)
        check(url.usePinned { mc_http_next_request(session.sessionId, outId.ptr, it.addressOf(0).reinterpret(), url.size, length.ptr, limit.ptr) } == 1)
        check(outId.value == id && limit.value == 3)
        val body = byteArrayOf(0, 127, -1)
        check(body.usePinned { mc_http_complete(session.sessionId, id, 400, it.addressOf(0).reinterpret(), body.size) } == 1)
        body[0] = 9
        val result = checkNotNull(session.take(id))
        check(result.state == MC_HTTP_RESPONSE.toInt() && result.status == 400 && result.body.contentEquals(byteArrayOf(0,127,-1)))
        check(mc_http_state(session.sessionId, id) == MC_HTTP_NOT_FOUND)
        val cancelled = session.begin("https://example.invalid/late", 3)
        check(session.cancel(cancelled))
        check(mc_http_fail(session.sessionId, cancelled, MC_HTTP_ERROR_IO.toInt()) == 0)
        check(session.take(cancelled)?.state == MC_HTTP_CANCELLED.toInt())
        session.close()
        check(mc_http_state(session.sessionId, cancelled) == MC_HTTP_NOT_FOUND)
        7
    } finally { session.close() }
}
