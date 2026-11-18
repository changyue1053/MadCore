package com.mad.core.time

import com.mad.core.extension.ServiceKey
import com.mad.core.extension.ServiceRegistry
import kotlin.time.ExperimentalTime
import kotlin.time.TimeSource

/*
 * 时钟（PT-01 契约；《mad-plat-line-plan》v0.2 §5.1，键表 §3.3）。
 *
 * 为什么在 L1：rules 禁止直取墙钟（detekt ForbiddenMethodCall 对 `System.currentTimeMillis` / `System.nanoTime` 判红），
 * 但 L1 此前没有时钟契约——只有 L2 的 `EngineClock`（capability-im-engine，`now()` 单值毫秒、只承诺单调不减）。
 * L1 / L3 / L5 各处于是各自 `kotlin.time.Clock.System.now()`（core-upgrade `wallClockMillis`、feature-conversation-impl、
 * shellkit-common 三处同口径而无共用面；三处今已全部改认 [Clock]，`gates/clock_direct_allow.txt` 0 行），JVM 仿真里时间不可控。本模块把时间来源收成一个 L1 契约：
 * 读时间的代码只认 [Clock]，装配决定它是系统时钟还是替身。
 *
 * 纪律：
 * - 墙钟 [Clock.epochMillis] 与单调钟 [Clock.elapsedNanos] 分开，两者禁止互换：墙钟只用于展示与持久时间戳；
 *   单调钟只用于间隔、超时、退避。墙钟会跳（系统校时、用户改时间），拿它算超时会算出负数或数小时；
 *   单调钟的起点是进程内任意一点，跨进程无意义，持久化它等于持久化一个随机数。
 * - 时间只经 [Clock]（plat-lane-rules 第 5 条）：本线代码禁止直取 `kotlin.time.Clock.System` 与 `TimeSource.Monotonic`，
 *   唯一例外是 [SystemClock]——全 KMP 侧唯一直取点。
 * - 取用：`services.clock()`（[clock]）。键 [ClockKey]（`core.time.clock`，AppScope 层）可选，未登记回落 [SystemClock]；
 *   测试与仿真登记替身（`FakeClock`，core-testing，PT-02）。因此本契约没有 `None`：缺席语义就是系统时钟。
 * - 与 `EngineClock` 的关系：不改它。引擎域继续持自己的 `EngineClock`；要让引擎读本时钟，由消费方（装配 / 能力域）
 *   以 [Clock.elapsedNanos] 换算毫秒去适配，本模块不依赖 capability-*，也不替引擎决定口径。
 * - 不做：时区与格式化（`HostLocaleFacts.timeZoneId` 在 core-shellhost，`Formats.relativeDay` 在 core-i18n）。
 */

/**
 * 时钟契约：两种读数、两种用途，禁止互换。
 *
 * 实现必须无副作用、可在任意线程调用，读数不抛出；替身实现由测试推进时间。
 */
interface Clock {
    /**
     * 墙钟毫秒（Unix epoch，UTC）：只用于展示与持久时间戳（消息时间、"上次检查"落盘）。
     * 会随系统校时跳变，禁止用它算间隔、超时、退避。
     */
    fun epochMillis(): Long

    /**
     * 单调纳秒：自进程内某一起点起的已流逝时间，非负且不减；只用于间隔、超时、退避。
     * 起点任意、跨进程无意义，禁止持久化，禁止与 [epochMillis] 混算。
     */
    fun elapsedNanos(): Long
}

/**
 * 系统时钟：全 KMP 侧唯一允许直取系统时间的位置（唯一直取点）。
 *
 * [epochMillis] 取 `kotlin.time.Clock.System`；[elapsedNanos] 取 `TimeSource.Monotonic` 对进程级起点 [origin] 的流逝量——
 * 起点在本对象首次被访问时打下，首次读数接近 0。禁止在别处再写这两处直取；需要时间的代码经 [clock] 取 [Clock]。
 */
object SystemClock : Clock {
    private val origin: TimeSource.Monotonic.ValueTimeMark = TimeSource.Monotonic.markNow()

    @OptIn(ExperimentalTime::class)
    override fun epochMillis(): Long = kotlin.time.Clock.System.now().toEpochMilliseconds()

    override fun elapsedNanos(): Long = origin.elapsedNow().inWholeNanoseconds
}

/** 时钟服务键（`core.time.clock`，AppScope 层，可选）：装配或测试登记；未登记回落 [SystemClock]，见 [clock]。 */
object ClockKey : ServiceKey<Clock> {
    override val id: String = "core.time.clock"
}

/**
 * 取时钟：登记了 [ClockKey] 返回登记值，未登记回落 [SystemClock]。
 * 消费方一律 `services.clock()`，不应 `require(ClockKey)`——键可选，缺席不是错。
 */
fun ServiceRegistry.clock(): Clock = get(ClockKey) ?: SystemClock
