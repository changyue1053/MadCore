package com.mad.core.extension

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFalse

/** 注册表纪律：装配期填充、运行期只读；重复键判错；缺登记的错误信息点名键 id。 */
class RegistriesTest {

    private object NameKey : ServiceKey<String> {
        override val id: String = "test.name"
    }

    private object CountKey : ServiceKey<Int> {
        override val id: String = "test.count"
    }

    private object Decorators : ExtensionPoint<String> {
        override val id: String = "test.decorators"
    }

    @Test
    fun `service registry returns what was put and null for absent keys`() {
        val registry = ServiceRegistry()
        registry.put(NameKey, "mad")
        assertEquals("mad", registry.get(NameKey))
        assertEquals("mad", registry.require(NameKey))
        assertNull(registry.get(CountKey))
    }

    @Test
    fun `service registry rejects duplicate keys`() {
        val registry = ServiceRegistry()
        registry.put(NameKey, "first")
        val failure = assertFailsWith<IllegalStateException> { registry.put(NameKey, "second") }
        assertEquals(true, failure.message.orEmpty().contains(NameKey.id))
        assertEquals("first", registry.require(NameKey), "失败的二次登记不覆盖首个值")
    }

    @Test
    fun `service registry is read-only after seal`() {
        val registry = ServiceRegistry()
        registry.put(NameKey, "mad")
        registry.seal()
        assertFailsWith<IllegalStateException> { registry.put(CountKey, 1) }
        assertEquals("mad", registry.require(NameKey))
        assertNull(registry.get(CountKey))
    }

    @Test
    fun `require on a missing key names the key id`() {
        val failure = assertFailsWith<IllegalStateException> { ServiceRegistry().require(CountKey) }
        assertEquals(true, failure.message.orEmpty().contains(CountKey.id))
    }

    // W28 A-01 ①：延后构造登记——键在装配期占位、实例首次 get 才构造（Settings / UpgradeChecker 挪出 T0 → APP_READY 窗口）。

    @Test
    fun `lazy registration constructs on first get and exactly once`() {
        val registry = ServiceRegistry()
        var built = 0
        registry.putLazy(NameKey) { built += 1; "mad-$built" }
        registry.seal()
        assertEquals(0, built, "登记与封口都不构造")
        assertEquals("mad-1", registry.get(NameKey))
        assertEquals("mad-1", registry.require(NameKey))
        assertEquals("mad-1", registry.get(NameKey))
        assertEquals(1, built, "只构造一次，之后同一实例")
    }

    @Test
    fun `lazy registration follows the same duplicate and seal discipline as put`() {
        val registry = ServiceRegistry()
        registry.putLazy(NameKey) { "lazy" }
        assertFailsWith<IllegalStateException> { registry.put(NameKey, "eager") }
        assertFailsWith<IllegalStateException> { registry.putLazy(NameKey) { "again" } }
        registry.put(CountKey, 1)
        registry.seal()
        assertFailsWith<IllegalStateException> { registry.putLazy(NameKey) { "late" } }
        assertEquals("lazy", registry.require(NameKey), "失败的二次登记不覆盖首个工厂")
        assertEquals(1, registry.require(CountKey))
    }

    @Test
    fun `lazy factory failure surfaces on get and is retried on the next get`() {
        val registry = ServiceRegistry()
        var attempts = 0
        registry.putLazy(CountKey) { attempts += 1; if (attempts == 1) error("first attempt fails") else 7 }
        val failure = assertFailsWith<IllegalStateException> { registry.get(CountKey) }
        assertEquals("first attempt fails", failure.message)
        assertEquals(7, registry.get(CountKey), "工厂抛出不缓存失败：下一次 get 重试")
        assertEquals(2, attempts)
    }

    // W29 A-01：工厂重入判错（自引用登记点名键 id，不再是 StackOverflowError）+ contains 不兑现探测。

    @Test
    fun `a lazy factory that reads its own key fails naming the key and is retried on the next get`() {
        val registry = ServiceRegistry()
        var attempts = 0
        registry.putLazy(NameKey) {
            attempts += 1
            // 首次：自引用（工厂内 require 同键）；第二次：正常构造——判错不缓存，下一次 get 仍走工厂。
            if (attempts == 1) "self=" + registry.require(NameKey) else "mad"
        }
        registry.seal()
        val failure = assertFailsWith<IllegalStateException> { registry.get(NameKey) }
        assertEquals(true, failure.message.orEmpty().contains(NameKey.id), "重入错误点名键 id：${failure.message}")
        assertEquals(true, failure.message.orEmpty().contains("重入"), "错误信息说明是工厂重入：${failure.message}")
        assertEquals("mad", registry.require(NameKey), "重入判错不缓存：下一次 get 重试并成功")
        assertEquals(2, attempts)
    }

    @Test
    fun `a lazy factory may read other keys including other lazy keys`() {
        val registry = ServiceRegistry()
        var countBuilt = 0
        registry.putLazy(CountKey) { countBuilt += 1; 41 }
        registry.putLazy(NameKey) { "count=" + registry.require(CountKey) }
        registry.seal()
        assertEquals("count=41", registry.require(NameKey), "工厂内读别的键（含别的延后键）不是重入")
        assertEquals(1, countBuilt)
    }

    @Test
    fun `contains reports registered keys without materializing lazy factories`() {
        val registry = ServiceRegistry()
        var built = 0
        registry.put(CountKey, 1)
        registry.putLazy(NameKey) { built += 1; "mad" }
        registry.seal()
        assertEquals(true, registry.contains(CountKey))
        assertEquals(true, registry.contains(NameKey), "putLazy 登记过即在册")
        assertEquals(0, built, "contains 不兑现工厂")
        assertEquals("mad", registry.require(NameKey))
        assertEquals(1, built)
        assertEquals(false, ServiceRegistry().contains(NameKey), "未登记的键不在册")
    }

    @Test
    fun `extension registry keeps registration order and is read-only after seal`() {
        val registry = ExtensionRegistry()
        assertEquals(emptyList(), registry.all(Decorators))
        registry.register(Decorators, "bot")
        registry.register(Decorators, "secret")
        registry.seal()
        assertFailsWith<IllegalStateException> { registry.register(Decorators, "late") }
        assertEquals(listOf("bot", "secret"), registry.all(Decorators))
    }

    // ---- W30 首日 ㊀：层叠查找（mad-shellhost-services-plan §4） ----

    @Test
    fun `layered registry falls back to the parent for get require and contains`() {
        val host = ServiceRegistry()
        host.put(NameKey, "from-host")
        host.seal()
        val app = ServiceRegistry.layered(host)

        assertEquals("from-host", app.get(NameKey), "自表未命中回落父表")
        assertEquals("from-host", app.require(NameKey))
        assertTrue(app.contains(NameKey), "contains 也回落父表——put-if-absent 守卫据此跳过壳已登记的键")
        assertNull(app.get(CountKey))
        assertFalse(app.contains(CountKey))
    }

    @Test
    fun `child registration shadows the parent and never writes into it`() {
        val host = ServiceRegistry()
        host.put(NameKey, "from-host")
        host.seal()
        val app = ServiceRegistry.layered(host)

        app.put(NameKey, "from-app")

        assertEquals("from-app", app.get(NameKey), "装配层登记胜过壳的可选登记（同键覆盖父表）")
        assertEquals("from-host", host.get(NameKey), "父表原值不动")
        assertEquals(setOf("test.name"), app.keys, "keys 只含自表（登记序）")
        assertEquals(setOf("test.name"), host.keys)
    }

    @Test
    fun `child put-lazy is not materialized by contains through the parent chain`() {
        val host = ServiceRegistry().also { it.seal() }
        val app = ServiceRegistry.layered(host)
        var built = 0
        app.putLazy(CountKey) { built += 1; 7 }

        assertTrue(app.contains(CountKey))
        assertEquals(0, built, "contains 不兑现工厂（层叠后同样成立）")
        assertEquals(7, app.get(CountKey))
        assertEquals(1, built)
    }

    @Test
    fun `sealing the child does not seal the parent and Empty is sealed`() {
        val host = ServiceRegistry()
        val app = ServiceRegistry.layered(host)
        app.seal()

        host.put(NameKey, "late-host-write")
        assertEquals("late-host-write", app.get(NameKey), "子表封口不影响父表；父表由属主封口")
        assertFailsWith<IllegalStateException> { ServiceRegistry.Empty.put(CountKey, 1) }
        assertTrue(ServiceRegistry.Empty.keys.isEmpty())
    }
}
