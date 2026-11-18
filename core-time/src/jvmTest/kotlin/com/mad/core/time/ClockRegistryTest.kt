package com.mad.core.time

import com.mad.core.extension.ServiceRegistry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

/** [clock] 的缺席语义：未登记 [ClockKey] 回落 [SystemClock]；登记了替身就返回替身，读数来自替身。 */
class ClockRegistryTest {

    /** 测试内替身：墙钟固定在 [fixedEpochMillis]，单调钟每读一次前进 [stepNanos]。 */
    private class StepClock(private val fixedEpochMillis: Long, private val stepNanos: Long) : Clock {
        private var elapsed = 0L

        override fun epochMillis(): Long = fixedEpochMillis

        override fun elapsedNanos(): Long {
            elapsed += stepNanos
            return elapsed
        }
    }

    @Test
    fun `clock falls back to SystemClock when the key is absent`() {
        assertSame(SystemClock, ServiceRegistry.Empty.clock())
        assertSame(SystemClock, ServiceRegistry().apply { seal() }.clock())
    }

    @Test
    fun `clock returns the registered clock and reads from it`() {
        val step = StepClock(fixedEpochMillis = 1_600_000_000_000L, stepNanos = 1_000L)
        val services = ServiceRegistry().apply {
            put(ClockKey, step)
            seal()
        }
        assertSame(step, services.clock())
        assertEquals(1_600_000_000_000L, services.clock().epochMillis())
        assertEquals(1_000L, services.clock().elapsedNanos())
        assertEquals(2_000L, services.clock().elapsedNanos())
    }
}
