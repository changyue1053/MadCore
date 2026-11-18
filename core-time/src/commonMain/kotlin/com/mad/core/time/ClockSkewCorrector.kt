package com.mad.core.time

import com.mad.core.extension.ServiceKey
import com.mad.core.extension.ServiceRegistry

/*
 * 时钟偏移校正入口（RFC-2026-006 §2.4，T-22 §3.4 定稿）：本文件只立位与缺席形态，策略实现（样本滤波、异常样本剔除）归 WP-X15。
 *
 * 纪律：
 * - 本文件不直取任何时间源（G-09-15 同文件的时钟偏移断言五守）；本机墙钟只经 `services.clock()`，即 [ClockKey] 登记的替身在这里同样生效。
 * - 缺席语义：键缺席与 [ClockSkewCorrector.None] 同义，偏移 0，校正墙钟等于 `clock().epochMillis()`，即现状。
 * - 校正墙钟只供展示及 RFC-2026-006 §4 已登记的判定用途；间隔、超时、退避只读 [Clock.elapsedNanos]，禁止把校正墙钟当服务端时间持久化。
 */

/** 服务端时间样本进、偏移出（展示及 §4 已登记判定用途）；单调钟不受影响。实现的本机墙钟只经构造注入的 Clock 读。 */
interface ClockSkewCorrector {
    /** serverEpochMillis：服务端墙钟毫秒；roundTripNanos：该次往返的 elapsedNanos 差。不抛、不阻塞。 */
    fun observe(serverEpochMillis: Long, roundTripNanos: Long)

    /** 偏移估计（毫秒，服务端墙钟减本机墙钟）；无样本为 0。 */
    fun skewMillis(): Long

    companion object {
        /** 恒零偏移，不读任何时间源；样本一律忽略。 */
        val None: ClockSkewCorrector = object : ClockSkewCorrector {
            override fun observe(serverEpochMillis: Long, roundTripNanos: Long) {}
            override fun skewMillis(): Long = 0L
        }
    }
}

/** 偏移校正键（`core.time.clock-skew`，AppScope，可选）：装配登记策略实现；缺席与 [ClockSkewCorrector.None] 同义。 */
object ClockSkewCorrectorKey : ServiceKey<ClockSkewCorrector> {
    override val id: String = "core.time.clock-skew"
}

/** 校正墙钟，只供展示及 §4 已登记判定用途；键缺席按 None，等于 clock().epochMillis()。禁止用它算间隔、超时、退避。 */
fun ServiceRegistry.correctedEpochMillis(): Long =
    clock().epochMillis() + (get(ClockSkewCorrectorKey) ?: ClockSkewCorrector.None).skewMillis()
