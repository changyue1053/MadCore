package com.mad.core.testkit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ManualClockTest {
    @Test fun advancesBothClocks() {
        val clock = ManualClock(100)
        clock.advanceMillis(12)
        assertEquals(112L, clock.epochMillis())
        assertEquals(12_000_000L, clock.elapsedNanos())
        clock.advanceMillis(0)
        assertEquals(112L, clock.epochMillis())
    }
    @Test fun wallCorrectionDoesNotChangeElapsed() {
        val clock = ManualClock(100)
        clock.advanceMillis(1)
        clock.setEpochMillis(-100)
        assertEquals(-100L, clock.epochMillis())
        assertEquals(1_000_000L, clock.elapsedNanos())
    }
    @Test fun invalidAdvanceIsAtomic() {
        val clock = ManualClock(Long.MAX_VALUE)
        for (duration in listOf(-1L, 1L, Long.MAX_VALUE)) {
            assertFailsWith<IllegalArgumentException> { clock.advanceMillis(duration) }
            assertEquals(Long.MAX_VALUE, clock.epochMillis())
            assertEquals(0L, clock.elapsedNanos())
        }
    }
    @Test fun elapsedOverflowIsAtomic() {
        val clock = ManualClock()
        val maxMillis = Long.MAX_VALUE / 1_000_000
        clock.advanceMillis(maxMillis)
        clock.setEpochMillis(0)
        assertFailsWith<IllegalArgumentException> { clock.advanceMillis(1) }
        assertEquals(0L, clock.epochMillis())
        assertEquals(maxMillis * 1_000_000, clock.elapsedNanos())
    }
}
