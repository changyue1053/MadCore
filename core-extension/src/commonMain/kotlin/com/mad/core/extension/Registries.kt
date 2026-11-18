package com.mad.core.extension

/*
 * 注册表（总控预置的 L1 契约骨架；《跨端产品线架构设计》§7）。
 *
 * 两种注册表，同一条纪律：装配期填充、运行期只读；底座与能力域不认识注册进来的具体实现，
 * 只按键（[ServiceKey]）或扩展点（[ExtensionPoint]）取用。这是 `if (product == X)` 的替代品。
 *
 * - [ServiceRegistry]：单值键。装配层把 Router、IM 账户句柄、Flags 等按键放入，消费方按键取；
 *   L1 模块之间借此解耦（core-scope 不依赖 core-router，却能经键拿到 Router）。
 * - [ExtensionRegistry]：多值扩展点。宿主（能力域 / 特性）声明扩展点，产品注册实现，宿主运行期遍历。
 */

/** 单值服务键：`object RouterKey : ServiceKey<Router>`。[id] 全仓唯一，重复注册判错。 */
interface ServiceKey<T : Any> {
    val id: String
}

/** 多值扩展点：`object MessageRenderers : ExtensionPoint<MessageRenderer>`。 */
interface ExtensionPoint<T : Any> {
    val id: String
}

/**
 * 装配期填充、运行期只读的单值注册表。
 *
 * 层叠查找（`mad-shellhost-services-plan.md` §4）：经 [layered] 建出的表带一张只读父表——[get] / [require] / [contains]
 * 自表未命中回落父表；[put] / [putLazy] / [seal] / [keys] 只作用于自表，子表同键**覆盖**父表（装配层登记胜过壳的可选登记）。
 * 用途：`AppScope.Builder` 以 `ShellHost.services`（壳提供的可选平台服务）为父表，装配 / 特性看见一张表，壳与装配各写各的；
 * 进程级全局 `HostServices` 因此不再有写者，已删。主构造器保持无参：带缺省参数会与 JVM 合成无参构造器撞 overload，K/N 也不导出缺省参数。
 */
class ServiceRegistry {
    /** 值或 [Deferred]（延后构造的占位）；[get] 处解包。 */
    private val services = LinkedHashMap<String, Any>()
    private var isSealed = false

    /** 只读父表；null = 单层表（既有行为）。 */
    private var parent: ServiceRegistry? = null

    /** 自表在册键（登记序，不含父表）：三端 `[shellkit] host-services=[…]` 留痕行的来源。 */
    val keys: Set<String> get() = services.keys.toSet()

    /**
     * 延后构造的登记占位（A-01 ①）。包一层而不是直接放 `Lazy`：服务本身合法地是 `Lazy<*>` 时不被误解包。
     * `lazy` 缺省 SYNCHRONIZED：首次 [get] 并发到达只构造一份；工厂抛出不缓存失败，下一次 [get] 重试（与 `Lazy` 契约一致）。
     *
     * 工厂重入判错（A-01）：工厂体内再 [get] / [require] 同键 = 自引用登记——JVM 上 `synchronized` 可重入、K/N 的 lazy 锁同样可重入，
     * 二者都会再次进入初始化体而不是等待，结果是 StackOverflowError（没有键名的深栈）。这里在初始化体入口看一眼 [isConstructing]：
     * 已在构造中即抛 `IllegalStateException` 并点名 `key.id`；异常沿工厂抛出、不缓存，标志位在 `finally` 复位，下一次 [get] 仍可重试。
     * 别的线程在同一时刻 [get] 走的是锁等待（不进初始化体），不会被误判为重入。
     */
    private class Deferred(private val keyId: String, factory: () -> Any) {
        private var isConstructing = false

        val value: Any by lazy {
            check(!isConstructing) { "ServiceRegistry 工厂重入：$keyId 的 putLazy 工厂内 get / require 了同键（自引用登记）" }
            isConstructing = true
            try {
                factory()
            } finally {
                isConstructing = false
            }
        }
    }

    /** 装配期登记；同键二次登记或封口后登记判错（防止运行期偷改装配）。 */
    fun <T : Any> put(key: ServiceKey<T>, value: T) {
        reserve(key)
        services[key.id] = value
    }

    /**
     * 延后构造的登记（A-01 ①，只加）：键在装配期占位、纪律与 [put] 完全相同（同键二次 / 封口后判错），实例在首次 [get] / [require]
     * 时由 [factory] 构造并缓存——把构造代价挪出 `AppScope` 构造窗口（T0 → APP_READY），首帧后按需兑现。
     * 适用：构造有 IO / 类装载代价、装配期无人读的服务（Settings / UpgradeChecker）；不适用：装配期有人 [get] 的服务（那等于立即构造，白占一层）。
     * [factory] 在首个读者的线程执行，读者须承受其代价与异常；缓存后线程无关。
     * 探测键在册请用 contains(key)，get 会兑现工厂。
     */
    fun <T : Any> putLazy(key: ServiceKey<T>, factory: () -> T) {
        reserve(key)
        services[key.id] = Deferred(key.id, factory)
    }

    private fun reserve(key: ServiceKey<*>) {
        check(!isSealed) { "ServiceRegistry 已封口：${key.id} 不能在运行期登记" }
        // 先查再放：重复登记判错时首个值必须原样保留（单测抓出的骨架缺陷——put 后再比对会先覆盖再抛）。
        check(key.id !in services) { "ServiceRegistry 重复登记：${key.id}" }
    }

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> get(key: ServiceKey<T>): T? = when (val stored = services[key.id]) {
        null -> parent?.get(key)
        is Deferred -> stored.value as T
        else -> stored as T
    }

    fun <T : Any> require(key: ServiceKey<T>): T =
        get(key) ?: error("ServiceRegistry 缺登记：${key.id}（检查产品清单的 capabilities / features 闭包）")

    /**
     * 键是否在册（A-01）：[put] 与 [putLazy] 登记过即 true，**不兑现** [putLazy] 的工厂。
     * put-if-absent 守卫（`if (!services.contains(Key)) services.put(Key, …)`）用它探测；
     * 用 `get(key) == null` 探测会把延后构造的服务当场建出来（把构造代价拉回 T0 → APP_READY 窗口）。
     */
    fun contains(key: ServiceKey<*>): Boolean = key.id in services || (parent?.contains(key) ?: false)

    /** 装配完成后封口，之后只读（只封自表；父表由其属主封口——`ShellHost.services` 交给装配前须已 `seal()`）。 */
    fun seal() { isSealed = true }

    companion object {
        /**
         * 建一张以 [parent] 为只读父表的层叠表：查找回落父表，登记只进自表。父表不要求已封口（K/N 导出面拿到的是壳持有的
         * 实例），但纪律要求壳在交出前 `seal()`；子表封口不影响父表。
         */
        fun layered(parent: ServiceRegistry): ServiceRegistry = ServiceRegistry().also { it.parent = parent }

        /** 封口空表：`ShellHost.services` 的缺省值——未注入任何可选平台服务的壳（仿真 / 预览 / 旧壳）。 */
        val Empty: ServiceRegistry = ServiceRegistry().also { it.seal() }
    }
}

/** 装配期填充、运行期只读的多值注册表。 */
class ExtensionRegistry {
    private val extensions = HashMap<String, MutableList<Any>>()
    private var isSealed = false

    fun <T : Any> register(point: ExtensionPoint<T>, extension: T) {
        check(!isSealed) { "ExtensionRegistry 已封口：${point.id} 不能在运行期注册" }
        extensions.getOrPut(point.id) { ArrayList() }.add(extension)
    }

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> all(point: ExtensionPoint<T>): List<T> = (extensions[point.id] ?: emptyList<Any>()) as List<T>

    fun seal() { isSealed = true }
}
