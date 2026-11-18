package com.mad.core.time

import kotlin.test.Test
import kotlin.test.assertTrue

/** [SystemClock] 两路读数的最低保证：单调钟非负且两次读数不减；墙钟晚于 2020-01-01（读到的是真实墙钟，不是 0 或起点）。 */
class SystemClockTest {

    @Test
    fun `elapsedNanos is non-negative and does not decrease across two reads`() {
        val first = SystemClock.elapsedNanos()
        val second = SystemClock.elapsedNanos()
        assertTrue(first >= 0L, "单调钟首次读数须非负，实得 $first")
        assertTrue(second >= first, "单调钟两次读数须不减，实得 $first 与 $second")
    }

    @Test
    fun `epochMillis is later than 2020-01-01`() {
        val now = SystemClock.epochMillis()
        assertTrue(now > EPOCH_MILLIS_2020_01_01, "墙钟读数须晚于 2020-01-01（$EPOCH_MILLIS_2020_01_01），实得 $now")
    }

    private companion object {
        /** `2020-01-01T00:00:00Z` 的 epoch 毫秒。 */
        const val EPOCH_MILLIS_2020_01_01: Long = 1_577_836_800_000L
    }
}
