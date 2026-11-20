package com.mad.core.net

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

class HttpTest {
    @Test fun methodBodyContractIsExplicit() {
        for (method in listOf(HttpMethod.GET, HttpMethod.DELETE)) {
            assertFailsWith<IllegalArgumentException> { HttpRequest("https://example.invalid", method, body = byteArrayOf(1)) }
        }
        for (method in listOf(HttpMethod.POST, HttpMethod.PUT)) {
            assertEquals(1, HttpRequest("https://example.invalid", method, body = byteArrayOf(1)).bodySize)
            assertEquals(0, HttpRequest("https://example.invalid", method).bodySize)
        }
    }

    @Test fun rejectUnsafeHeadersAndUrls() {
        for (url in listOf("file:///secret", "https://user:pass@example.invalid", "https://example.invalid/#secret", "https://example.invalid/\n")) {
            assertFailsWith<IllegalArgumentException> { HttpRequest(url) }
        }
        for (headers in listOf(mapOf("X-Test" to "a\r\nb"), mapOf("Content-Length" to "10"), mapOf("A" to "1", "a" to "2"))) {
            assertFailsWith<IllegalArgumentException> { HttpRequest("https://example.invalid", headers = headers) }
        }
    }
    @Test fun copiesPayloadAndRedactsDiagnostics() {
        val bytes = byteArrayOf(1)
        val request = HttpRequest("https://example.invalid?token=private", HttpMethod.POST, body = bytes)
        bytes[0] = 2
        request.body[0] = 3
        assertEquals(1.toByte(), request.body[0])
        assertFalse(request.toString().contains("private"))
    }
    @Test fun secureDefaultAndRequestLimitRejectBeforeTransport() {
        var calls = 0
        val transport = object : HttpTransport {
            override fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse {
                calls++; return HttpResponse(200, emptyMap(), byteArrayOf())
            }
        }
        val client = HttpClient(transport, HttpLimits(maxRequestBytes = 1))
        assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> { client.execute(HttpRequest("http://example.invalid")) }.failure)
        assertEquals(HttpFailure.RequestTooLarge, assertFailsWith<HttpTransportException> { client.execute(HttpRequest("https://example.invalid", HttpMethod.POST, body = byteArrayOf(1, 2))) }.failure)
        assertEquals(0, calls)
    }
    @Test fun responseLimitAndNoClientRetries() {
        var calls = 0
        val client = HttpClient(object : HttpTransport {
            override fun execute(request: HttpRequest, limits: HttpLimits): HttpResponse {
                calls++; return HttpResponse(200, emptyMap(), byteArrayOf(1, 2))
            }
        }, HttpLimits(maxResponseBytes = 1))
        assertEquals(HttpFailure.ResponseTooLarge, assertFailsWith<HttpTransportException> { client.execute(HttpRequest("https://example.invalid")) }.failure)
        assertEquals(1, calls)
    }
}
