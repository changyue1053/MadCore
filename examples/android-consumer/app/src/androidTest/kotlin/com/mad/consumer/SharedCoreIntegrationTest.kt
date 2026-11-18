package com.mad.consumer
import com.mad.core.storage.StringStore
import example.upper.Alpha
import example.upper.Beta
import org.junit.Assert.*
import org.junit.Test

class SharedCoreIntegrationTest {
    @Test fun twoIndependentAarsShareCore() {
        val store = Alpha.create()
        assertSame(store, Beta.consume(store))
        assertEquals("beta", store.get("shared"))
        assertSame(Alpha.type(), Beta.type())
        assertSame(StringStore::class.java, Alpha.type())
    }
}
