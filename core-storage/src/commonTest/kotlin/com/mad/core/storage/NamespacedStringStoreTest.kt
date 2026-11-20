package com.mad.core.storage

import kotlin.test.*

class NamespacedStringStoreTest {
    @Test fun instancesAreIsolatedAndReopenable() {
        val backend = MemoryStringStore()
        val first = NamespacedStringStore(backend, "first")
        val second = NamespacedStringStore(backend, "second")
        first.put("preferences.theme", "dark")
        second.put("preferences.theme", "light")
        assertEquals("dark", NamespacedStringStore(backend, "first").get("preferences.theme"))
        assertEquals("light", second.get("preferences.theme"))
        first.remove("preferences.theme")
        assertNull(first.get("preferences.theme"))
        assertEquals("light", second.get("preferences.theme"))
        assertEquals("NamespacedStringStore", first.toString())
    }
    @Test fun namespacesAndLogicalKeysHaveUnambiguousBounds() {
        val backend = MemoryStringStore()
        for (invalid in listOf("", "Upper", "a.b", "1abc", "a".repeat(33))) {
            assertEquals(StorageFailure.InvalidKey,
                assertFailsWith<StorageException> { NamespacedStringStore(backend, invalid) }.failure)
        }
        val store = NamespacedStringStore(backend, "a".repeat(32))
        store.put("b".repeat(95), "")
        assertEquals("", backend.get("a".repeat(32) + "." + "b".repeat(95)))
        for (invalid in listOf("", "Upper", "a b", "b".repeat(96))) {
            assertFailsWith<StorageException> { store.get(invalid) }
            assertFailsWith<StorageException> { store.put(invalid, "ignored") }
            assertFailsWith<StorageException> { store.remove(invalid) }
        }
        assertFailsWith<StorageException> { store.put("value", "a".repeat(65537)) }
    }
}
