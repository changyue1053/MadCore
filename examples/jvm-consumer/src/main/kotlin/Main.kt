import com.mad.core.extension.ServiceRegistry
import com.mad.core.json.MiniJson
import com.mad.core.testkit.ManualClock
import com.mad.core.time.ClockKey
import com.mad.core.time.clock

fun main() {
    val services = ServiceRegistry()
    val clock = ManualClock(100)
    services.put(ClockKey, clock)
    services.seal()
    clock.advanceMillis(25)
    check(services.clock().epochMillis() == 125L)
    check(MiniJson.parseObject("{\"ready\":true}")?.get("ready") == true)
    println("MadCore artifact-only JVM consumer passed")
}
