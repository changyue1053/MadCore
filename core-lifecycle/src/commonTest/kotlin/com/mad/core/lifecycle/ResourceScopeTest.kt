package com.mad.core.lifecycle

import kotlin.test.*

class ResourceScopeTest {
    @Test fun lifoDetachAndIdempotentClose() {
        val events = mutableListOf<Int>()
        val scope = ResourceScope()
        scope.register { events.add(1) }
        val released = scope.register { events.add(2) }
        scope.register { events.add(3) }
        assertTrue(released.detach())
        assertFalse(released.detach())
        val report = scope.close()
        assertEquals(listOf(3, 1), events)
        assertEquals(2, report.attempted)
        assertEquals(0, report.failed)
        assertTrue(scope.isClosed)
        assertEquals(0, scope.close().attempted)
        assertEquals(listOf(3, 1), events)
    }

    @Test fun failuresAreIsolatedAndReentrancyCannotReclaimOwnedResources() {
        val events = mutableListOf<Int>()
        val scope = ResourceScope()
        val first = scope.register { events.add(1) }
        scope.register { throw IllegalStateException("private diagnostic") }
        scope.register {
            assertEquals(0, scope.close().attempted)
            assertFalse(first.detach())
            assertFailsWith<ScopeClosedException> { scope.register { events.add(9) } }
            events.add(3)
        }
        val report = scope.close()
        assertEquals(listOf(3, 1), events)
        assertEquals(3, report.attempted)
        assertEquals(1, report.failed)
        assertFalse(scope.toString().contains("private"))
    }

    @Test fun fatalFailureIsRethrownAfterRemainingCleanup() {
        val scope = ResourceScope()
        val events = mutableListOf<Int>()
        scope.register { events.add(1) }
        val fatal = AssertionError("fatal")
        scope.register { throw fatal }
        scope.register { events.add(3) }
        assertSame(fatal, assertFailsWith<AssertionError> { scope.close() })
        assertEquals(listOf(3, 1), events)
        assertTrue(scope.isClosed)
        assertEquals(0, scope.close().attempted)
    }

    @Test fun rejectionDoesNotTakeOwnershipAndDuplicatesAreExplicit() {
        val scope = ResourceScope()
        var calls = 0
        val resource = CloseableResource { calls++ }
        scope.register(resource)
        scope.register(resource)
        assertEquals(2, scope.close().attempted)
        assertEquals(2, calls)
        assertFailsWith<ScopeClosedException> { scope.register(resource) }
        assertEquals(2, calls)
    }
}
