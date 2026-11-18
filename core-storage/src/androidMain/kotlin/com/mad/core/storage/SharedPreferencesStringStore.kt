package com.mad.core.storage

import android.content.SharedPreferences

/**
 * Synchronous, unencrypted string storage backed by a host-supplied preference file.
 * Hosts should supply an isolated file and call this adapter off the main thread.
 * No enumeration, clearing, transactions, or cross-process coordination is provided.
 * A failed commit may already have changed the platform's in-memory state.
 */
class SharedPreferencesStringStore(private val preferences: SharedPreferences) : StringStore {
    @Throws(StorageException::class)
    override fun get(key: String): String? {
        checkStorageKey(key)
        try {
            val value = try {
                preferences.getString(key, null)
            } catch (_: ClassCastException) {
                throw StorageException(StorageFailure.InvalidValue)
            }
            if (value != null) checkStorageValue(value)
            return value
        } catch (failure: StorageException) {
            throw failure
        } catch (_: Exception) {
            throw StorageException(StorageFailure.Backend)
        }
    }

    @Throws(StorageException::class)
    override fun put(key: String, value: String) {
        checkStorageKey(key)
        checkStorageValue(value)
        try {
            if (!preferences.edit().putString(key, value).commit()) {
                throw StorageException(StorageFailure.Backend)
            }
        } catch (failure: StorageException) {
            throw failure
        } catch (_: Exception) {
            throw StorageException(StorageFailure.Backend)
        }
    }

    @Throws(StorageException::class)
    override fun remove(key: String) {
        checkStorageKey(key)
        try {
            if (!preferences.edit().remove(key).commit()) {
                throw StorageException(StorageFailure.Backend)
            }
        } catch (failure: StorageException) {
            throw failure
        } catch (_: Exception) {
            throw StorageException(StorageFailure.Backend)
        }
    }
}
