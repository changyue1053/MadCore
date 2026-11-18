package com.mad.consumer

import android.content.Context
import android.content.SharedPreferences
import androidx.test.platform.app.InstrumentationRegistry
import com.mad.core.storage.SharedPreferencesStringStore
import com.mad.core.storage.StorageException
import com.mad.core.storage.StorageFailure
import org.junit.Assert.*
import org.junit.Test

/** Exercises the published Android adapter; never clears or enumerates preferences. */
class StorageIntegrationTest {
    private fun fails(expected: StorageFailure, block: () -> Unit) {
        try {
            block()
            fail("Expected $expected")
        } catch (failure: StorageException) {
            assertEquals(expected, failure.failure)
            assertNull(failure.cause)
        }
    }

    @Test fun publishedStorageAndPlatformPersistence() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences("madcore_storage_integration", Context.MODE_PRIVATE)
        val key = "test.value"
        val typedKey = "test.typed"
        assertTrue(preferences.edit().remove(key).remove(typedKey).commit())
        try {
            val store = SharedPreferencesStringStore(preferences)
            assertNull(store.get(key))
            store.remove(key)
            store.put(key, "first")
            // New adapter over the same host file must see completed writes.
            val reopened = SharedPreferencesStringStore(
                context.getSharedPreferences("madcore_storage_integration", Context.MODE_PRIVATE)
            )
            assertEquals("first", reopened.get(key))
            reopened.put(key, "second")
            assertEquals("second", store.get(key))
            store.put(key, "")
            assertEquals("", reopened.get(key))
            val limitValue = "a".repeat(65_536)
            store.put(key, limitValue)
            assertEquals(limitValue, reopened.get(key))
            fails(StorageFailure.ValueTooLarge) { store.put(key, "a".repeat(65_537)) }
            // UTF-8 byte count, not UTF-16 String.length, governs the cap.
            fails(StorageFailure.ValueTooLarge) { store.put(key, "é".repeat(32_769)) }
            assertEquals(limitValue, reopened.get(key))
            fails(StorageFailure.InvalidKey) { store.get("Uppercase") }
            fails(StorageFailure.InvalidKey) { store.put("bad key", "ignored") }
            fails(StorageFailure.InvalidKey) { store.remove("") }
            assertTrue(preferences.edit().putInt(typedKey, 7).commit())
            fails(StorageFailure.InvalidValue) { store.get(typedKey) }
            // External data is checked too, rather than silently escaping the cap.
            assertTrue(preferences.edit().putString(typedKey, "a".repeat(65_537)).commit())
            fails(StorageFailure.ValueTooLarge) { store.get(typedKey) }
            reopened.remove(key)
            assertNull(store.get(key))
            reopened.remove(key)
        } finally {
            // Only keys owned by this test; no clear() or unrelated user data.
            assertTrue(preferences.edit().remove(key).remove(typedKey).commit())
        }
    }

    @Test fun failedCommitsAndPlatformErrorsAreRedacted() {
        val preferences = InstrumentationRegistry.getInstrumentation().targetContext
            .getSharedPreferences("madcore_storage_integration", Context.MODE_PRIVATE)
        val rejectedWrites = object : SharedPreferences by preferences {
            override fun edit(): SharedPreferences.Editor {
                val editor = preferences.edit()
                return object : SharedPreferences.Editor by editor {
                    override fun putString(key: String?, value: String?): SharedPreferences.Editor = this
                    override fun remove(key: String?): SharedPreferences.Editor = this
                    override fun commit(): Boolean = false
                }
            }
        }
        val store = SharedPreferencesStringStore(rejectedWrites)
        fails(StorageFailure.Backend) { store.put("test.value", "private value") }
        fails(StorageFailure.Backend) { store.remove("test.value") }
        val brokenReads = object : SharedPreferences by preferences {
            override fun getString(key: String?, defValue: String?): String? {
                throw IllegalStateException("private platform diagnostic")
            }
        }
        try {
            SharedPreferencesStringStore(brokenReads).get("test.value")
            fail("Expected backend failure")
        } catch (failure: StorageException) {
            assertEquals(StorageFailure.Backend, failure.failure)
            assertNull(failure.cause)
            assertFalse(failure.toString().contains("private"))
        }
    }
}
