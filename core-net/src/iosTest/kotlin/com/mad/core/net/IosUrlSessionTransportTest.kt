@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core.net

import platform.darwin.*
import kotlin.test.Test
import kotlin.test.assertEquals
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

    @Test fun actualLoopbackRequestsAndPolicies() {
        val base = "http://127.0.0.1:18082"
        val client = HttpClient(IosUrlSessionTransport(), HttpLimits(allowInsecureHttp = true))
        fun execute(path: String) = offMain { client.execute(HttpRequest(base + path)) }
        assertEquals("hello", execute("/ok").body.decodeToString())
        val post = offMain { client.execute(HttpRequest("$base/post", HttpMethod.POST, body = "payload".encodeToByteArray())) }
        assertEquals(201, post.status)
        assertEquals("payload", post.body.decodeToString())
        assertEquals(302, execute("/redirect").status)
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
        assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> {
            offMain { IosUrlSessionTransport().execute(HttpRequest("$base/ok"), HttpLimits()) }
        }.failure)
    }
}
