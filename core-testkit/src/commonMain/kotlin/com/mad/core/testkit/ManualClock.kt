package com.mad.core.testkit

import com.mad.core.time.Clock

/**
 * Deterministic clock for tests. Not thread-safe; advance it from the test's owner thread.
 * Wall-clock adjustments never change elapsed time. This module is opt-in, not in madcore.
 */
class ManualClock(initialEpochMillis: Long = 0L) : Clock {
    private var epoch = initialEpochMillis
    private var elapsed = 0L

    override fun epochMillis(): Long = epoch
    override fun elapsedNanos(): Long = elapsed

    /** Simulates wall-clock correction, including backwards jumps. */
    fun setEpochMillis(value: Long) { epoch = value }

    /** Advances both clocks; rejects negative durations and overflow without changing either clock. */
    fun advanceMillis(millis: Long) {
        require(millis >= 0) { "Duration must be non-negative" }
        require(millis <= Long.MAX_VALUE / NANOS_PER_MILLI) { "Duration overflows nanoseconds" }
        val nanos = millis * NANOS_PER_MILLI
        require(epoch <= Long.MAX_VALUE - millis) { "Wall clock overflow" }
        require(elapsed <= Long.MAX_VALUE - nanos) { "Elapsed clock overflow" }
        epoch += millis
        elapsed += nanos
    }

    private companion object { const val NANOS_PER_MILLI = 1_000_000L }
}
