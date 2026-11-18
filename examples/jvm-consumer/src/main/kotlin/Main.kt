import com.mad.core.extension.ServiceRegistry
import com.mad.core.json.MiniJson
import com.mad.core.testkit.ManualClock
import com.mad.core.time.ClockKey
import com.mad.core.time.clock

fun main() {
    val store = com.mad.core.storage.MemoryStringStore()
    store.put("theme", "dark")
    check(store.get("theme") == "dark")
    store.remove("theme")
    check(store.get("theme") == null)
    val request = com.mad.core.net.HttpRequest("https://example.invalid")
    check(request.method == com.mad.core.net.HttpMethod.GET)
    val transport: com.mad.core.net.HttpTransport = com.mad.core.net.UrlConnectionTransport()
    check(transport is com.mad.core.net.UrlConnectionTransport)
    val config = com.mad.core.config.ConfigSnapshot(mapOf("timeout" to "10"))
        .overlay(com.mad.core.config.ConfigSnapshot(mapOf("timeout" to "20")))
    check(config.longValue("timeout") == 20L)
    val logger = com.mad.core.logging.StructuredLogger()
    check(logger.record(com.mad.core.logging.LogLevel.Info, "consumer", "ready",
        privacy = com.mad.core.logging.FieldPrivacy.Public))
    check(!logger.record(com.mad.core.logging.LogLevel.Info, "consumer", "sensitive"))
    val services = ServiceRegistry()
    val clock = ManualClock(100)
    services.put(ClockKey, clock)
    services.seal()
    clock.advanceMillis(25)
    check(services.clock().epochMillis() == 125L)
    check(MiniJson.parseObject("{\"ready\":true}")?.get("ready") == true)
    println("MadCore artifact-only JVM consumer passed")
}
