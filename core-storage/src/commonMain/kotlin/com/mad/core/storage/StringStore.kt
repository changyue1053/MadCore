package com.mad.core.storage

enum class StorageFailure { InvalidKey, ValueTooLarge, InvalidValue, Backend }

/** Never includes stored data, keys, platform messages or underlying exception causes. */
class StorageException(val failure: StorageFailure) : Exception("Storage failure: $failure")

/**
 * Non-secret, bounded string preferences. Missing is null; an empty string is a value.
 * Keys: lowercase ASCII identifiers, 1..128 chars. Values: at most 65536 UTF-8 bytes.
 * No enumeration, clear-all, transactions, encryption, cross-process coordination or crash durability.
 * Read-modify-write is NOT atomic. Host owns the backend namespace, backup policy and scheduling.
 * Backend errors do not promise rollback: a failed write may already affect in-memory state.
 */
interface StringStore {
    @Throws(StorageException::class)
    fun get(key: String): String?
    @Throws(StorageException::class)
    fun put(key: String, value: String)
    @Throws(StorageException::class)
    fun remove(key: String)
}

internal fun checkStorageKey(key: String) {
    if (key.length !in 1..128 || key[0] !in 'a'..'z' ||
        key.any { it !in 'a'..'z' && it !in '0'..'9' && it !in "_.-" }) {
        throw StorageException(StorageFailure.InvalidKey)
    }
}

internal fun checkStorageValue(value: String) {
    if (value.length > 65536 || value.encodeToByteArray().size > 65536) {
        throw StorageException(StorageFailure.ValueTooLarge)
    }
}

/** Single-threaded, process-memory only. Caller must synchronize access if shared. */
class MemoryStringStore : StringStore {
    private val values = mutableMapOf<String, String>()
    @Throws(StorageException::class)
    override fun get(key: String): String? {
        checkStorageKey(key)
        return values[key]
    }
    @Throws(StorageException::class)
    override fun put(key: String, value: String) {
        checkStorageKey(key)
        checkStorageValue(value)
        values[key] = value
    }
    @Throws(StorageException::class)
    override fun remove(key: String) {
        checkStorageKey(key)
        values.remove(key)
    }
    override fun toString(): String = "MemoryStringStore"
}
