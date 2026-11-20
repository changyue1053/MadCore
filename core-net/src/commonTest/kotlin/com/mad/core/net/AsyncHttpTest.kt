package com.mad.core.net

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.assertNull
import kotlin.test.assertIs
import kotlin.test.assertFailsWith

class AsyncHttpTest {
    @Test fun pendingPollDoesNotConsume() {
        val e = AsyncHttpExchange()
        repeat(3) { assertNull(e.call.poll()) }
        assertEquals(AsyncHttpState.Pending, e.call.state)
        assertFalse(e.call.isDrained)
    }

    @Test fun oneResultTransferredAndReleasedByCell() {
        val e = AsyncHttpExchange()
        assertTrue(e.publish(AsyncHttpResult.Response(HttpResponse(400, emptyMap(), byteArrayOf(1)))))
        assertEquals(AsyncHttpState.Ready, e.call.state)
        assertEquals(400, assertIs<AsyncHttpResult.Response>(e.call.poll()).response.status)
        assertEquals(AsyncHttpState.Consumed, e.call.state)
        assertNull(e.call.poll())
        assertFalse(e.publish(AsyncHttpResult.Failure(HttpFailure.Io)))
        assertFalse(e.call.cancel())
        assertFalse(e.call.isDrained)
        e.markDrained(); e.markDrained()
        assertTrue(e.call.isDrained)
    }

    @Test fun cancellationIsNotDrainAndLateCompletionLoses() {
        val e = AsyncHttpExchange()
        assertTrue(e.call.cancel())
        assertFalse(e.call.cancel())
        assertFalse(e.publish(AsyncHttpResult.Failure(HttpFailure.Timeout)))
        assertFalse(e.call.isDrained)
        assertEquals(AsyncHttpResult.Cancelled, e.call.poll())
        assertTrue(e.isCancellationRequested)
        assertFalse(e.call.isDrained)
        e.markDrained()
        assertTrue(e.call.isDrained)
        assertNull(e.call.poll())
    }

    @Test fun completionWinsOverCancellationBeforePolling() {
        val e = AsyncHttpExchange()
        assertTrue(e.publish(AsyncHttpResult.Failure(HttpFailure.Io)))
        assertFalse(e.call.cancel())
        assertFalse(e.isCancellationRequested)
        e.markDrained()
        assertEquals(HttpFailure.Io, assertIs<AsyncHttpResult.Failure>(e.call.poll()).failure)
        assertTrue(e.call.isDrained)
    }

    @Test fun timeoutDoesNotProveDrain() {
        val e = AsyncHttpExchange()
        e.publish(AsyncHttpResult.Failure(HttpFailure.Timeout))
        assertEquals(HttpFailure.Timeout, assertIs<AsyncHttpResult.Failure>(e.call.poll()).failure)
        assertFalse(e.call.isDrained)
    }

    @Test fun rejectPrematureDrainWithoutChangingState() {
        val e = AsyncHttpExchange()
        assertFailsWith<IllegalStateException> { e.markDrained() }
        assertEquals(AsyncHttpState.Pending, e.call.state)
        assertFalse(e.call.isDrained)
        assertTrue(e.call.cancel())
    }

    @Test fun oversizedBodyBecomesSanitizedFailure() {
        val e = AsyncHttpExchange(HttpLimits(maxResponseBytes = 1))
        assertTrue(e.publish(AsyncHttpResult.Response(HttpResponse(200, emptyMap(), byteArrayOf(1, 2)))))
        assertEquals(HttpFailure.ResponseTooLarge, assertIs<AsyncHttpResult.Failure>(e.call.poll()).failure)
        assertFalse(e.call.isDrained)
    }

    @Test fun copiedResponseAndSeparateInstances() {
        val a = AsyncHttpExchange(); val b = AsyncHttpExchange()
        val bytes = byteArrayOf(1)
        val values = mutableListOf("original")
        val headers = mutableMapOf<String, List<String>>("X-Test" to values)
        val response = HttpResponse(200, headers, bytes)
        a.publish(AsyncHttpResult.Response(response))
        bytes[0] = 9; values[0] = "changed"; headers.clear()
        val owned = assertIs<AsyncHttpResult.Response>(a.call.poll()).response
        assertEquals(1.toByte(), owned.body[0])
        assertEquals(listOf("original"), owned.headers["X-Test"])
        assertEquals(AsyncHttpState.Pending, b.call.state)
        b.call.cancel(); assertFalse(a.call.isDrained)
    }
}
