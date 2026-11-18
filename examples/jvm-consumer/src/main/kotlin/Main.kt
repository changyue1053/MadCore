import com.mad.core.extension.ServiceRegistry
import com.mad.core.json.MiniJson
import com.mad.core.testkit.ManualClock
import com.mad.core.time.ClockKey
import com.mad.core.time.clock

fun main() {
    val shared = example.alpha.UpperAlpha.createStore()
    check(example.beta.UpperBeta.useStore(shared) === shared)
    check(shared.get("upper.beta") == "shared")
    check(example.alpha.UpperAlpha.coreType() === example.beta.UpperBeta.coreType())
    check(example.alpha.UpperAlpha.coreType() === com.mad.core.storage.StringStore::class.java)
    val alphaSource = example.alpha.UpperAlpha::class.java.protectionDomain.codeSource.location
    val betaSource = example.beta.UpperBeta::class.java.protectionDomain.codeSource.location
    check(alphaSource != betaSource && alphaSource.path.endsWith(".jar") && betaSource.path.endsWith(".jar"))
    println("Two independent upper SDK JARs exchange one identical Core instance/type")
    val scripted = com.mad.core.testkit.ScriptedHttpTransport()
    scripted.enqueueResponse(com.mad.core.net.HttpResponse(200, emptyMap(), "fixture".encodeToByteArray()))
    val fakeClient = com.mad.core.net.HttpClient(scripted)
    check(fakeClient.execute(com.mad.core.net.HttpRequest("https://example.invalid")).body.decodeToString() == "fixture")
    scripted.assertExhausted()

    var closed = false
    val scope = com.mad.core.lifecycle.ResourceScope()
    scope.register { closed = true }
    check(scope.close().attempted == 1 && closed)

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
