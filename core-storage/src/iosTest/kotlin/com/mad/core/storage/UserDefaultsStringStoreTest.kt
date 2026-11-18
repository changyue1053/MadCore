package com.mad.core.storage

import platform.Foundation.NSUserDefaults
import platform.Foundation.NSUUID
import kotlin.test.*

class UserDefaultsStringStoreTest {
    @Test fun nativeDefaultsRoundTripAndTypeSafety() {
        val suite = "com.mad.core.test." + NSUUID().UUIDString
        val defaults = NSUserDefaults(suiteName = suite)
        val store = UserDefaultsStringStore(defaults)
        try {
            assertNull(store.get("value"))
            store.put("value", "你好")
            assertEquals("你好", UserDefaultsStringStore(NSUserDefaults(suiteName = suite)).get("value"))
            store.put("value", "")
            assertEquals("", store.get("value"))
            store.remove("value")
            assertNull(store.get("value"))
            defaults.setBool(true, forKey = "typed")
            assertEquals(StorageFailure.InvalidValue,
                assertFailsWith<StorageException> { store.get("typed") }.failure)
            assertEquals(StorageFailure.ValueTooLarge,
                assertFailsWith<StorageException> { store.put("value", "a".repeat(65537)) }.failure)
            assertNull(store.get("value"))
        } finally {
            defaults.removeObjectForKey("value")
            defaults.removeObjectForKey("typed")
        }
    }
}
