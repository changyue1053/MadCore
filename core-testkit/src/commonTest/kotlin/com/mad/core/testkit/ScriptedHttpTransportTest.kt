package com.mad.core.testkit

import com.mad.core.net.*
import kotlin.test.*

class ScriptedHttpTransportTest {
    private val request = HttpRequest("https://example.invalid/private?token=secret")
    @Test fun fifoFailureAndExhaustionAreExplicit() {
        val transport = ScriptedHttpTransport()
        val client = HttpClient(transport)
        transport.enqueueResponse(HttpResponse(200, emptyMap(), "one".encodeToByteArray()))
        transport.enqueueFailure(HttpFailure.Timeout)
        transport.enqueueResponse(HttpResponse(404, emptyMap(), byteArrayOf()))
        assertEquals("one", client.execute(request).body.decodeToString())
        assertEquals(HttpFailure.Timeout, assertFailsWith<HttpTransportException> { client.execute(request) }.failure)
        assertEquals(404, client.execute(request).status)
        assertEquals(3, transport.callCount)
        transport.assertExhausted()
        val empty = assertFailsWith<IllegalStateException> { client.execute(request) }
        assertFalse(empty.toString().contains("secret"))
        assertEquals(3, transport.callCount)
    }
    @Test fun preflightDoesNotConsumeButOversizedResponseDoes() {
        val transport = ScriptedHttpTransport()
        transport.enqueueResponse(HttpResponse(200, emptyMap(), byteArrayOf(1, 2)))
        assertFailsWith<IllegalStateException> { transport.assertExhausted() }
        assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> {
            transport.execute(HttpRequest("http://example.invalid"), HttpLimits())
        }.failure)
        assertEquals(HttpFailure.RequestTooLarge, assertFailsWith<HttpTransportException> {
            transport.execute(HttpRequest(request.url, HttpMethod.PUT, body = byteArrayOf(1, 2)), HttpLimits(maxRequestBytes = 1))
        }.failure)
        assertEquals(1, transport.pendingCount)
        assertEquals(0, transport.callCount)
        assertEquals(HttpFailure.ResponseTooLarge, assertFailsWith<HttpTransportException> {
            transport.execute(request, HttpLimits(maxResponseBytes = 1))
        }.failure)
        transport.assertExhausted()
        assertEquals(1, transport.callCount)
        assertFalse(transport.toString().contains("secret"))
    }
    @Test fun distinctInstancesAndResponseCopiesRemainIsolated() {
        val first = ScriptedHttpTransport()
        val second = ScriptedHttpTransport()
        val input = byteArrayOf(1)
        first.enqueueResponse(HttpResponse(200, mapOf("x-test" to listOf("a")), input))
        input[0] = 9
        val result = first.execute(request, HttpLimits())
        result.body[0] = 8
        assertEquals(1.toByte(), result.body[0])
        assertEquals(0, second.callCount)
        assertFailsWith<IllegalStateException> { second.execute(request, HttpLimits()) }
    }
}
