package com.mad.core.time

import com.mad.core.extension.ServiceRegistry
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * [ClockSkewCorrector] 立位与缺席形态（RFC-2026-006 §2.4、§4）：键缺席与 [ClockSkewCorrector.None] 同义，
 * 校正墙钟 = 经 [ClockKey] 注入的墙钟 + 偏移；时间只经注入的替身，单调钟不参与。
 */
class ClockSkewCorrectorTest {

    /** 墙钟替身：读数由测试设定；单调钟一读即抛，证明校正墙钟只读墙钟。 */
    private class WallClock(var epoch: Long) : Clock {
        override fun epochMillis(): Long = epoch

        override fun elapsedNanos(): Long = error("校正墙钟不应读单调钟")
    }

    /** 偏移替身：固定偏移，样本忽略。 */
    private class FixedSkew(private val skew: Long) : ClockSkewCorrector {
        override fun observe(serverEpochMillis: Long, roundTripNanos: Long) {}

        override fun skewMillis(): Long = skew
    }

    private fun registry(clock: Clock, corrector: ClockSkewCorrector? = null): ServiceRegistry = ServiceRegistry().apply {
        put(ClockKey, clock)
        corrector?.let { put(ClockSkewCorrectorKey, it) }
        seal()
    }

    @Test
    fun `None stays zero skew and observe tolerates extreme samples`() {
        val none = ClockSkewCorrector.None
        none.observe(Long.MAX_VALUE, -1L)
        none.observe(Long.MIN_VALUE, Long.MAX_VALUE)
        none.observe(0L, 0L)
        assertEquals(0L, none.skewMillis())
    }

    @Test
    fun `key id is the literal from the RFC key table`() {
        assertEquals("core.time.clock-skew", ClockSkewCorrectorKey.id)
    }

    @Test
    fun `absent key yields the wall clock injected through ClockKey`() {
        assertEquals(1_700_000_000_000L, registry(WallClock(1_700_000_000_000L)).correctedEpochMillis())
    }

    @Test
    fun `registered None yields the same value as the absent key`() {
        val wall = WallClock(1_700_000_000_000L)
        assertEquals(1_700_000_000_000L, registry(wall, ClockSkewCorrector.None).correctedEpochMillis())
    }

    @Test
    fun `registered corrector adds a positive skew and subtracts a negative one`() {
        assertEquals(1_700_000_001_500L, registry(WallClock(1_700_000_000_000L), FixedSkew(1_500L)).correctedEpochMillis())
        assertEquals(1_699_999_998_000L, registry(WallClock(1_700_000_000_000L), FixedSkew(-2_000L)).correctedEpochMillis())
    }

    @Test
    fun `corrected wall clock follows the injected clock on every read`() {
        val wall = WallClock(1_700_000_000_000L)
        val services = registry(wall, FixedSkew(250L))
        assertEquals(1_700_000_000_250L, services.correctedEpochMillis())
        wall.epoch = 1_700_000_060_000L
        assertEquals(1_700_000_060_250L, services.correctedEpochMillis())
    }
}
