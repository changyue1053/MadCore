@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core.net

import platform.darwin.*
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class IosUrlSessionTransportTest {
    private fun offMain(block: () -> HttpResponse): HttpResponse {
        var response: HttpResponse? = null
        var failure: Throwable? = null
        val done = dispatch_semaphore_create(0)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT.toLong(), 0u)) {
            try { response = block() } catch (caught: Throwable) { failure = caught }
            finally { dispatch_semaphore_signal(done) }
        }
        check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 35_000_000_000L)) == 0L) { "Worker did not complete" }
        failure?.let { throw it }
        return response!!
    }

    @Test fun untrustedTlsIsRejected() {
        val client = HttpClient(IosUrlSessionTransport(), HttpLimits(allowInsecureHttp = true))
        fun get(path: String) = offMain { client.execute(HttpRequest("http://127.0.0.1:18082" + path)) }
        assertEquals("ready", get("/tls-ready").body.decodeToString())
        assertEquals("0", get("/tls-count").body.decodeToString())
        val attempts = get("/tls-attempts").body.decodeToString().toInt()
        assertEquals(HttpFailure.Io, assertFailsWith<HttpTransportException> {
            offMain { client.execute(HttpRequest("https://127.0.0.1:18443/tls-probe")) }
        }.failure)
        assertTrue(get("/tls-attempts").body.decodeToString().toInt() > attempts)
        assertEquals("0", get("/tls-count").body.decodeToString())
        assertEquals("hello", get("/ok").body.decodeToString())
    }
    @Test fun actualLoopbackRequestsAndPolicies() {
        val base = "http://127.0.0.1:18082"
        val client = HttpClient(IosUrlSessionTransport(), HttpLimits(allowInsecureHttp = true))
        fun execute(path: String) = offMain { client.execute(HttpRequest(base + path)) }
        assertEquals("hello", execute("/ok").body.decodeToString())
        val post = offMain { client.execute(HttpRequest("$base/post", HttpMethod.POST, body = "payload".encodeToByteArray())) }
        for (payload in listOf("payload", "")) {
            assertEquals("PUT:$payload", offMain { client.execute(HttpRequest("$base/methods", HttpMethod.PUT,
                body = payload.encodeToByteArray())) }.body.decodeToString())
        }
        assertEquals("DELETE:", offMain { client.execute(HttpRequest("$base/methods", HttpMethod.DELETE)) }.body.decodeToString())
        assertEquals(201, post.status)
        assertEquals("payload", post.body.decodeToString())
        assertEquals("0", execute("/redirect-count").body.decodeToString())
        assertEquals(302, execute("/redirect").status)
        assertEquals("0", execute("/redirect-count").body.decodeToString()) // server proves target never reached
        assertEquals(400, execute("/error").status)
        for (path in listOf("/ok", "/chunked")) {
            val small = HttpClient(IosUrlSessionTransport(), HttpLimits(maxResponseBytes = 4, allowInsecureHttp = true))
            assertEquals(HttpFailure.ResponseTooLarge, assertFailsWith<HttpTransportException> {
                offMain { small.execute(HttpRequest(base + path)) }
            }.failure)
        }
        val impatient = HttpClient(IosUrlSessionTransport(callTimeoutMillis = 100), HttpLimits(allowInsecureHttp = true))
        assertEquals(HttpFailure.Timeout, assertFailsWith<HttpTransportException> {
            offMain { impatient.execute(HttpRequest("$base/slow")) }
        }.failure)
        assertEquals("hello", execute("/ok").body.decodeToString()) // a timed-out session must not poison the next call
        for (port in listOf(0, 65536)) {
            assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> {
                offMain { client.execute(HttpRequest("http://127.0.0.1:$port/ok")) }
            }.failure)
        }
        assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> {
            offMain { IosUrlSessionTransport().execute(HttpRequest("$base/ok"), HttpLimits()) }
        }.failure)
    }
}
