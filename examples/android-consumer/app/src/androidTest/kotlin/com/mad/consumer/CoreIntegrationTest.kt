package com.mad.consumer

import com.mad.core.config.ConfigSnapshot
import com.mad.core.net.*
import org.junit.Assert.*
import org.junit.Test

/** Runs on Android, consuming published AARs only; no SDK project dependency. */
class CoreIntegrationTest {
    private val base = "http://10.0.2.2:18082"
    private fun client(max: Int = 1024, timeout: Int = 3000) = HttpClient(
        UrlConnectionTransport(),
        HttpLimits(readTimeoutMillis = timeout, maxResponseBytes = max, allowInsecureHttp = true)
    )
    private fun fails(expected: HttpFailure, block: () -> Unit) {
        try { block(); fail("Expected $expected") }
        catch (e: HttpTransportException) { assertEquals(expected, e.failure) }
    }
    @Test fun untrustedTlsIsRejected() {
        val client = client(timeout = 5000)
        assertEquals("ready", client.execute(HttpRequest("$base/tls-ready")).body.decodeToString())
        assertEquals("0", client.execute(HttpRequest("$base/tls-count")).body.decodeToString())
        val attempts = client.execute(HttpRequest("$base/tls-attempts")).body.decodeToString().toInt()
        fails(HttpFailure.Io) { client.execute(HttpRequest("https://10.0.2.2:18443/tls-probe")) }
        assertTrue(client.execute(HttpRequest("$base/tls-attempts")).body.decodeToString().toInt() > attempts)
        assertEquals("0", client.execute(HttpRequest("$base/tls-count")).body.decodeToString())
        assertEquals("hello", client.execute(HttpRequest("$base/ok")).body.decodeToString())
    }
    @Test fun trustedTlsIsAccepted() {
        val counters = client(timeout = 5000)
        val before = counters.execute(HttpRequest("$base/android-tls-count")).body.decodeToString().toInt()
        // Use the production transport and its usual HTTPS verification. The
        // disposable Debug host, not the SDK, supplies the exact fixture trust.
        val https = HttpClient(UrlConnectionTransport(), HttpLimits(readTimeoutMillis = 5000))
        val response = https.execute(HttpRequest("https://10.0.2.2:28443/tls-probe"))
        assertEquals(200, response.status)
        assertEquals("hello", response.body.decodeToString())
        assertEquals(before + 1,
            counters.execute(HttpRequest("$base/android-tls-count")).body.decodeToString().toInt())
    }
    @Test fun publishedCoreAndRealHttp() {
        assertEquals(7L, ConfigSnapshot(mapOf("count" to "7")).longValue("count"))
        val client = client()
        assertEquals("hello", client.execute(HttpRequest("$base/ok")).body.decodeToString())
        val posted = client.execute(HttpRequest("$base/echo", HttpMethod.POST, body = "payload".encodeToByteArray()))
        for (payload in listOf("payload", "")) {
            assertEquals("PUT:$payload", client.execute(HttpRequest("$base/methods", HttpMethod.PUT,
                body = payload.encodeToByteArray())).body.decodeToString())
        }
        assertEquals("DELETE:", client.execute(HttpRequest("$base/methods", HttpMethod.DELETE)).body.decodeToString())
        assertEquals(201, posted.status)
        assertEquals("payload", posted.body.decodeToString())
        assertEquals(400, client.execute(HttpRequest("$base/error")).status)
        assertEquals("0", client.execute(HttpRequest("$base/redirect-count")).body.decodeToString())
        assertEquals(302, client.execute(HttpRequest("$base/redirect")).status)
        assertEquals("0", client.execute(HttpRequest("$base/redirect-count")).body.decodeToString()) // server-side no-follow evidence
        fails(HttpFailure.InvalidRequest) { HttpClient(UrlConnectionTransport()).execute(HttpRequest("$base/ok")) }
        fails(HttpFailure.ResponseTooLarge) { client(max = 2).execute(HttpRequest("$base/ok")) }
        fails(HttpFailure.ResponseTooLarge) { client(max = 8).execute(HttpRequest("$base/chunked")) }
        fails(HttpFailure.Timeout) { client(timeout = 100).execute(HttpRequest("$base/slow")) }
        assertEquals(200, client.execute(HttpRequest("$base/ok")).status)
    }
}
