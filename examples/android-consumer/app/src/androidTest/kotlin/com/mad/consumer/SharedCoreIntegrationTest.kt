package com.mad.consumer
import androidx.test.platform.app.InstrumentationRegistry
import com.mad.core.MadCoreInfo
import com.mad.core.storage.StringStore
import example.upper.Alpha
import example.upper.Beta
import org.junit.Assert.*
import org.junit.Test

class SharedCoreIntegrationTest {
    @Test fun twoIndependentAarsShareCore() {
        val expectedVersion = requireNotNull(
            InstrumentationRegistry.getArguments().getString("madcoreExpectedCoreVersion")
        ) { "Missing independent MadCore version expectation" }
        assertFalse("Empty independent MadCore version expectation", expectedVersion.isBlank())
        assertEquals("Packaged MadCore version", expectedVersion, MadCoreInfo.version)

        val store = Alpha.create()
        assertSame(store, Beta.consume(store))
        assertEquals("beta", store.get("shared"))
        assertSame(Alpha.type(), Beta.type())
        assertSame(StringStore::class.java, Alpha.type())
    }
}
