package com.mad.core.net

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class UrlConnectionTransportTest {
    @Test fun directAdapterRejectsCleartext() {
        assertEquals(HttpFailure.InvalidRequest, assertFailsWith<HttpTransportException> {
            UrlConnectionTransport().execute(HttpRequest("http://127.0.0.1:1"), HttpLimits())
        }.failure)
    }

    @Test fun realLoopbackGetPostErrorsRedirectAndBodyLimit() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val targetCalls = AtomicInteger()
        server.createContext("/ok") { exchange ->
            targetCalls.incrementAndGet()
            val body = "hello".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.createContext("/post") { exchange ->
            val body = exchange.requestBody.use { it.readBytes() }
            exchange.sendResponseHeaders(201, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.createContext("/redirect") { exchange ->
            exchange.responseHeaders.add("Location", "/ok")
            exchange.sendResponseHeaders(302, -1); exchange.close()
        }
        server.createContext("/error") { exchange ->
            val body = "bad".toByteArray()
            exchange.sendResponseHeaders(400, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.createContext("/chunked") { exchange ->
            exchange.sendResponseHeaders(200, 0)
            exchange.responseBody.use { it.write(ByteArray(20)) }
        }
        server.createContext("/slow") { exchange ->
            Thread.sleep(200)
            try { exchange.sendResponseHeaders(204, -1) } finally { exchange.close() }
        }
        server.start()
        try {
            val base = "http://127.0.0.1:${server.address.port}"
            val client = HttpClient(UrlConnectionTransport(), HttpLimits(allowInsecureHttp = true))
            assertEquals("hello", client.execute(HttpRequest("$base/ok")).body.decodeToString())
            val post = client.execute(HttpRequest("$base/post", HttpMethod.POST, body = "payload".encodeToByteArray()))
            assertEquals(201, post.status); assertEquals("payload", post.body.decodeToString())
            val error = client.execute(HttpRequest("$base/error"))
            assertEquals(400, error.status); assertEquals("bad", error.body.decodeToString())
            assertEquals(302, client.execute(HttpRequest("$base/redirect")).status)
            assertEquals(1, targetCalls.get())
            val small = HttpClient(UrlConnectionTransport(), HttpLimits(maxResponseBytes = 4, allowInsecureHttp = true))
            for (path in listOf("/ok", "/chunked")) {
                assertEquals(HttpFailure.ResponseTooLarge, assertFailsWith<HttpTransportException> { small.execute(HttpRequest(base + path)) }.failure)
            }
            val impatient = HttpClient(UrlConnectionTransport(), HttpLimits(readTimeoutMillis = 25, allowInsecureHttp = true))
            assertEquals(HttpFailure.Timeout, assertFailsWith<HttpTransportException> { impatient.execute(HttpRequest("$base/slow")) }.failure)
        } finally { server.stop(0) }
    }
}
