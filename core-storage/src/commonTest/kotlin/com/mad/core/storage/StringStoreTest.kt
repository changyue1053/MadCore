package com.mad.core.storage

import kotlin.test.*

class StringStoreTest {
    @Test fun missingEmptyOverwriteRemoveAndIsolation() {
        val a = MemoryStringStore()
        val b = MemoryStringStore()
        assertNull(a.get("key"))
        a.put("key", "")
        assertEquals("", a.get("key"))
        a.put("key", "next")
        assertEquals("next", a.get("key"))
        assertNull(b.get("key"))
        a.remove("key")
        a.remove("key")
        assertNull(a.get("key"))
    }
    @Test fun validationAndNoMutationOnRejectedWrite() {
        val s = MemoryStringStore()
        s.put("key", "old")
        for (key in listOf("", "UPPER", "a/b", "é", "a".repeat(129))) {
            assertEquals(StorageFailure.InvalidKey, assertFailsWith<StorageException> { s.get(key) }.failure)
            assertFailsWith<StorageException> { s.put(key, "private") }
            assertFailsWith<StorageException> { s.remove(key) }
        }
        s.put("exact", "é".repeat(32768))
        assertEquals(StorageFailure.ValueTooLarge,
            assertFailsWith<StorageException> { s.put("key", "é".repeat(32769)) }.failure)
        for (invalid in listOf("\uD800", "\uDC00", "\uD800x")) {
            assertEquals(StorageFailure.InvalidValue,
                assertFailsWith<StorageException> { s.put("key", invalid) }.failure)
        }
        s.put("unicode", "😀")
        assertEquals("😀", s.get("unicode"))
        assertEquals("old", s.get("key"))
        assertEquals(65536, s.get("exact")!!.encodeToByteArray().size)
        assertFalse(s.toString().contains("old"))
        val e = StorageException(StorageFailure.Backend)
        assertNull(e.cause)
    }
}
