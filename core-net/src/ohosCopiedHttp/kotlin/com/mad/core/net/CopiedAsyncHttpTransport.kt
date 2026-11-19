@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core.net

import com.mad.core.net.copied.*
import kotlinx.cinterop.*
import platform.posix.memcpy

/**
 * Experimental Harmony transport. The ArkTS RCP driver must create, pump and close
 * [sessionId] on the same host-selected owner loop as these Kotlin calls. Kotlin
 * keeps only numeric IDs: no native pointers, callbacks or continuations survive a call.
 * A closed or missing session invalidates outstanding delivery; it is not proof
 * that platform callbacks or network work have drained.
 */
class CopiedAsyncHttpTransport(
    private val sessionId: Int,
    private val callTimeoutMillis: Int = 30_000,
) : AsyncHttpTransport {
    init { require(sessionId > 0 && callTimeoutMillis in 1..120_000) }

    override fun start(request: HttpRequest, limits: HttpLimits): AsyncHttpCall {
        if (request.bodySize > minOf(limits.maxRequestBytes, BODY_CAP)) return reject(HttpFailure.RequestTooLarge)
        if (request.url.isEmpty() || request.url.length > URL_CAP ||
            request.url.any { it !in '!'..'~' } ||
            request.url.startsWith("http://") && !limits.allowInsecureHttp ||
            limits.connectTimeoutMillis > 120_000 || limits.readTimeoutMillis > 120_000
        ) return reject(HttpFailure.InvalidRequest)
        val headers = CopiedHttpHeaders.encode(request.headers) ?: return reject(HttpFailure.InvalidRequest)
        val url = request.url.encodeToByteArray()
        val body = request.body
        val operation = memScoped {
            val native = alloc<mc_http_request>()
            native.method = when (request.method) {
                HttpMethod.GET -> MC_HTTP_GET.toInt()
                HttpMethod.POST -> MC_HTTP_POST.toInt()
                HttpMethod.PUT -> MC_HTTP_PUT.toInt()
                HttpMethod.DELETE -> MC_HTTP_DELETE.toInt()
            }
            native.url_length = url.size
            native.url.copyIn(url)
            native.headers_length = headers.size
            native.headers.copyIn(headers)
            native.body_length = body.size
            native.body.copyIn(body)
            native.max_response = minOf(limits.maxResponseBytes, BODY_CAP)
            native.connect_timeout_ms = limits.connectTimeoutMillis
            native.read_timeout_ms = limits.readTimeoutMillis
            native.call_timeout_ms = callTimeoutMillis
            native.allow_insecure = if (limits.allowInsecureHttp) 1 else 0
            mc_http_begin_request(sessionId, native.ptr)
        }
        return if (operation > 0) Call(sessionId, operation)
        else reject(if (operation == MC_HTTP_INVALID_ARGUMENT) HttpFailure.InvalidRequest else HttpFailure.Io)
    }

    companion object {
        private const val URL_CAP = 2048
        private const val BODY_CAP = 65_536

        // Harness entry points only. A normal caller keeps the AsyncHttpCall returned by start.
        fun operationId(call: AsyncHttpCall): Int? = (call as? Call)?.operation
        fun resumeCall(session: Int, operation: Int): AsyncHttpCall = Call(session, operation)

        private fun reject(failure: HttpFailure): AsyncHttpCall = AsyncHttpExchange().run {
            publish(AsyncHttpResult.Failure(failure))
            markDrained()
            call
        }

        private fun CPointer<UByteVar>.copyIn(bytes: ByteArray) {
            if (bytes.isNotEmpty()) bytes.usePinned { memcpy(this, it.addressOf(0), bytes.size.convert()) }
        }
    }

    private class Call(private val session: Int, val operation: Int) : AsyncHttpCall {
        private var consumed = false
        override val isDrained: Boolean get() = false
        override val state: AsyncHttpState
            get() = when {
                consumed -> AsyncHttpState.Consumed
                mc_http_state(session, operation) == MC_HTTP_PENDING.toInt() -> AsyncHttpState.Pending
                else -> AsyncHttpState.Ready
            }

        override fun cancel(): Boolean = !consumed && mc_http_cancel(session, operation) == 1

        override fun poll(): AsyncHttpResult? {
            if (state != AsyncHttpState.Ready) return null
            return memScoped {
                val state = alloc<IntVar>()
                val error = alloc<IntVar>()
                val response = alloc<mc_http_response>()
                val code = mc_http_poll_response(session, operation, state.ptr, error.ptr, response.ptr, 1)
                if (code == 0) return@memScoped null
                consumed = true
                if (code == MC_HTTP_NOT_FOUND) return@memScoped AsyncHttpResult.Cancelled
                if (code != 1) return@memScoped AsyncHttpResult.Failure(HttpFailure.Io)
                when (state.value) {
                    MC_HTTP_CANCELLED.toInt() -> AsyncHttpResult.Cancelled
                    MC_HTTP_FAILURE.toInt() -> AsyncHttpResult.Failure(when (error.value) {
                        MC_HTTP_ERROR_TIMEOUT.toInt() -> HttpFailure.Timeout
                        MC_HTTP_ERROR_TOO_LARGE.toInt() -> HttpFailure.ResponseTooLarge
                        else -> HttpFailure.Io
                    })
                    MC_HTTP_RESPONSE.toInt() -> try {
                        require(response.body_length in 0..BODY_CAP && response.headers_length in 1..copiedHeaderCap)
                        val headers = CopiedHttpHeaders.decode(response.headers.reinterpret<ByteVar>().readBytes(response.headers_length))
                        val body = response.body.reinterpret<ByteVar>().readBytes(response.body_length)
                        AsyncHttpResult.Response(HttpResponse(response.status, headers, body))
                    } catch (_: Exception) {
                        AsyncHttpResult.Failure(HttpFailure.Io)
                    }
                    else -> AsyncHttpResult.Failure(HttpFailure.Io)
                }
            }
        }
    }
}
