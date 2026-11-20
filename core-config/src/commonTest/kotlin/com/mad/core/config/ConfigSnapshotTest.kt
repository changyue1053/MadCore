package com.mad.core.config

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConfigSnapshotTest {
    @Test fun inputMutationCannotChangeSnapshot() {
        val input = mutableMapOf("endpoint" to "old")
        val snapshot = ConfigSnapshot(input)
        input["endpoint"] = "new"
        input["extra"] = "added"
        assertEquals("old", snapshot.stringValue("endpoint"))
        assertEquals(1, snapshot.size)
        assertFalse(snapshot.contains("extra"))
    }

    @Test fun overlayIsImmutableAndLastLayerWins() {
        val base = ConfigSnapshot(mapOf("mode" to "default", "timeout" to "10"))
        val environment = ConfigSnapshot(mapOf("mode" to "staging"))
        val result = base.overlay(environment).overlay(ConfigSnapshot(mapOf("mode" to "local")))
        assertEquals("local", result.stringValue("mode"))
        assertEquals(10L, result.longValue("timeout"))
        assertEquals("default", base.stringValue("mode"))
        assertEquals("staging", environment.stringValue("mode"))
    }

    @Test fun missingAndEmptyAreDistinct() {
        val snapshot = ConfigSnapshot(mapOf("blank" to ""))
        assertTrue(snapshot.contains("blank"))
        assertEquals("", snapshot.stringValue("blank"))
        assertNull(snapshot.stringValue("missing"))
        assertNull(snapshot.booleanValue("missing"))
        assertNull(snapshot.longValue("missing"))
        assertNull(snapshot.doubleValue("missing"))
        assertFailsWith<ConfigValueException> { snapshot.booleanValue("blank") }
        assertEquals("", ConfigSnapshot(mapOf("blank" to "before")).overlay(snapshot).stringValue("blank"))
    }

    @Test fun booleansAreStrict() {
        assertEquals(true, ConfigSnapshot(mapOf("flag" to "true")).booleanValue("flag"))
        assertEquals(false, ConfigSnapshot(mapOf("flag" to "false")).booleanValue("flag"))
        for (invalid in listOf("TRUE", "1", "yes", " false", "")) {
            assertFailsWith<ConfigValueException> { ConfigSnapshot(mapOf("flag" to invalid)).booleanValue("flag") }
        }
    }

    @Test fun longBoundariesAndMalformedValues() {
        for (value in listOf(Long.MIN_VALUE, 0L, Long.MAX_VALUE)) {
            assertEquals(value, ConfigSnapshot(mapOf("count" to value.toString())).longValue("count"))
        }
        for (invalid in listOf("9223372036854775808", "-9223372036854775809", "1.0", " 2", "2 ", "")) {
            assertFailsWith<ConfigValueException> { ConfigSnapshot(mapOf("count" to invalid)).longValue("count") }
        }
    }

    @Test fun doublesMustBeFinite() {
        assertEquals(125.0, ConfigSnapshot(mapOf("ratio" to "1.25e2")).doubleValue("ratio"))
        for (invalid in listOf("NaN", "Infinity", "-Infinity", "1e999", " 1.0", "1.0 ", "bad", "0x1.0p2", "1.0f")) {
            assertFailsWith<ConfigValueException> { ConfigSnapshot(mapOf("ratio" to invalid)).doubleValue("ratio") }
        }
    }

    @Test fun rejectsInvalidKeys() {
        for (invalid in listOf("", "Upper", "9starts", "space key", "url?query", "a\n", "a".repeat(129))) {
            assertFailsWith<IllegalArgumentException> { ConfigSnapshot(mapOf(invalid to "value")) }
        }
        assertEquals(1, ConfigSnapshot(mapOf("a".repeat(128) to "value")).size)
    }

    @Test fun diagnosticsDoNotLeakValues() {
        val value = "private-test-value"
        val snapshot = ConfigSnapshot(mapOf("flag" to value))
        val failure = assertFailsWith<ConfigValueException> { snapshot.booleanValue("flag") }
        assertEquals("flag", failure.key)
        assertEquals("boolean", failure.expectedType)
        assertFalse(failure.toString().contains(value))
        assertEquals("ConfigSnapshot(size=1)", snapshot.toString())
    }

    @Test fun emptySnapshotIsReusable() {
        val layered = ConfigSnapshot.Empty.overlay(ConfigSnapshot(mapOf("mode" to "test")))
        assertEquals(0, ConfigSnapshot.Empty.size)
        assertEquals("test", layered.stringValue("mode"))
    }
}
