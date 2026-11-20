package com.mad.core.storage

/**
 * Logical key partition over a host-owned backend, not a security boundary.
 * Namespace: 1..32 lowercase ASCII letters/digits/_/- starting with a letter, no dots.
 * Logical keys: normal storage grammar, maximum 95 chars. Physical key is namespace.key.
 * The disjoint namespace grammar prevents ambiguous prefix combinations.
 * Does not own/close/flush backend, encrypt values or synchronize callers.
 */
class NamespacedStringStore @Throws(StorageException::class) constructor(
    private val backend: StringStore,
    private val namespace: String,
) : StringStore {
    init {
        if (namespace.length !in 1..32 || namespace[0] !in 'a'..'z' ||
            namespace.any { it !in 'a'..'z' && it !in '0'..'9' && it !in "_-" }) {
            throw StorageException(StorageFailure.InvalidKey)
        }
    }
    private fun physicalKey(key: String): String {
        checkStorageKey(key)
        if (key.length > 95) throw StorageException(StorageFailure.InvalidKey)
        return "$namespace.$key"
    }
    @Throws(StorageException::class)
    override fun get(key: String): String? = backend.get(physicalKey(key))
    @Throws(StorageException::class)
    override fun put(key: String, value: String) = backend.put(physicalKey(key), value)
    @Throws(StorageException::class)
    override fun remove(key: String) = backend.remove(physicalKey(key))
    override fun toString(): String = "NamespacedStringStore"
}
