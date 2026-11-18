package com.mad.consumer

import com.mad.core.lifecycle.ResourceScope
import org.junit.Assert.*
import org.junit.Test

class LifecycleIntegrationTest {
    @Test fun publishedLifecycleOwnership() {
        val scope = ResourceScope()
        val calls = mutableListOf<Int>()
        scope.register { calls.add(1) }
        val detached = scope.register { calls.add(2) }
        scope.register { throw IllegalStateException("private") }
        scope.register { calls.add(3) }
        assertTrue(detached.detach())
        val report = scope.close()
        assertEquals(listOf(3, 1), calls)
        assertEquals(3, report.attempted)
        assertEquals(1, report.failed)
        assertEquals(0, scope.close().attempted)
    }
}
