@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class, kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core

import com.mad.core.net.*
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.readBytes

/** Device harness only: value IDs cross the ABI; no Kotlin call object is retained by ArkTS. */
@CName("madcore_copied_http_test_start")
fun copiedHttpTestStart(session: Int, urlBytes: CPointer<ByteVar>?, length: Int, scenario: Int): Int = try {
    require(urlBytes != null && length in 1..2048 && scenario in 1..11)
    val url = urlBytes.readBytes(length).decodeToString(throwOnInvalidSequence = true)
    // This harness must never turn an arbitrary string into a network destination.
    val protocol = if (scenario == 9) "https" else "http"
    val endpoints = when (scenario) {
        1 -> setOf("ok")
        2, 10, 11 -> setOf("echo")
        3, 5 -> setOf("slow")
        4 -> setOf("chunked")
        6 -> setOf("error")
        7 -> setOf("bridge-headers")
        8 -> setOf("redirect")
        else -> setOf("tls-probe")
    }
    require(Regex("^$protocol://127\\.0\\.0\\.1:[1-9][0-9]{0,4}/[a-z-]+$").matches(url))
    require(url.substringAfter("127.0.0.1:").substringBefore('/').toInt() <= 65535)
    require(url.substringAfterLast('/') in endpoints)
    val request = when (scenario) {
        2, 10 -> HttpRequest(url, if (scenario == 2) HttpMethod.POST else HttpMethod.PUT,
            headers = mapOf("X-Copied-Request" to "probe"), body = "body".encodeToByteArray())
        11 -> HttpRequest(url, HttpMethod.DELETE)
        else -> HttpRequest(url)
    }
    val limits = HttpLimits(
        connectTimeoutMillis = 2_000,
        readTimeoutMillis = if (scenario == 5) 100 else 2_000,
        maxResponseBytes = if (scenario == 4) 8 else 1024,
        allowInsecureHttp = scenario != 9,
    )
    val call = CopiedAsyncHttpTransport(session, if (scenario == 5) 50 else 30_000).start(request, limits)
    CopiedAsyncHttpTransport.operationId(call) ?: -1
} catch (_: Exception) { -1 }

@CName("madcore_copied_http_test_poll")
fun copiedHttpTestPoll(session: Int, operation: Int, scenario: Int): Int = try {
    require(scenario in 1..11)
    val result = CopiedAsyncHttpTransport.resumeCall(session, operation).poll()
    if (result == null) 0 else {
        val ok = when (scenario) {
            3 -> result === AsyncHttpResult.Cancelled
            4 -> result is AsyncHttpResult.Failure && result.failure == HttpFailure.ResponseTooLarge
            5 -> result is AsyncHttpResult.Failure && result.failure == HttpFailure.Timeout
            9 -> result is AsyncHttpResult.Failure && result.failure == HttpFailure.Io
            else -> {
                val response = (result as? AsyncHttpResult.Response)?.response
                val expected = when (scenario) {
                    2 -> "POST:body"
                    10 -> "PUT:body"
                    11 -> "DELETE:"
                    6 -> "bad"
                    8 -> ""
                    else -> "hello"
                }
                fun header(name: String) = response?.headers?.entries?.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
                val status = when (scenario) { 6 -> 400; 8 -> 302; else -> 200 }
                response != null && response.status == status && response.body.contentEquals(expected.encodeToByteArray()) &&
                    header("Content-Length") == listOf(expected.length.toString()) &&
                    (scenario != 7 || header("X-Madcore-Test") == listOf("present")) &&
                    (scenario != 8 || header("Location") == listOf("/redirect-target"))
            }
        }
        if (ok) 1 else -1
    }
} catch (_: Exception) { -1 }

@CName("madcore_copied_http_test_cancel")
fun copiedHttpTestCancel(session: Int, operation: Int): Int =
    if (CopiedAsyncHttpTransport.resumeCall(session, operation).cancel()) 1 else 0
