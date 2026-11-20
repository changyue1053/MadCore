package com.mad.core.storage

import platform.Foundation.NSUserDefaults

/**
 * Host supplies an isolated defaults suite. NSUserDefaults writes disk asynchronously;
 * successful put/remove only acknowledges the in-process update, NOT crash-safe persistence.
 * Search-list/registered defaults can reappear after remove; do not register fallback keys in this suite.
 * Not Keychain, encryption or secret storage. Host must provide applicable privacy-manifest reasons.
 * No synchronize() call: Apple documents it as unnecessary. Objective-C NSExceptions are not caught.
 */
class UserDefaultsStringStore(private val defaults: NSUserDefaults) : StringStore {
    // Inherit StringStore's @Throws filter for the Objective-C/Swift bridge.
    override fun get(key: String): String? {
        checkStorageKey(key)
        val value = defaults.objectForKey(key) ?: return null
        if (value !is String) throw StorageException(StorageFailure.InvalidValue)
        checkStorageValue(value)
        return value
    }

    override fun put(key: String, value: String) {
        checkStorageKey(key)
        checkStorageValue(value)
        defaults.setObject(value, forKey = key)
    }

    override fun remove(key: String) {
        checkStorageKey(key)
        defaults.removeObjectForKey(key)
    }

    override fun toString(): String = "UserDefaultsStringStore"
}
