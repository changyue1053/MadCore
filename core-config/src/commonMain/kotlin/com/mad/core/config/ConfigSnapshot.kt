package com.mad.core.config

/** Invalid typed value. The original value is deliberately excluded from the error message. */
class ConfigValueException(val key: String, val expectedType: String) :
    IllegalArgumentException("Configuration '$key' is not a valid $expectedType")

/**
 * Immutable, string-backed configuration suitable for sharing between readers.
 * Copies inputs; changes create a new snapshot. No global state, I/O, remote protocol or persistence.
 * Keys are short lowercase ASCII identifiers, starting with a letter.
 *
 * Missing keys return null. Present but malformed typed values throw [ConfigValueException],
 * so invalid configuration is not silently mistaken for a missing value. Values are not trimmed.
 * Do not put secrets in source control. This class does not encrypt or securely erase strings.
 */
class ConfigSnapshot(values: Map<String, String>) {
    private val values: Map<String, String> = values.toMap().also { copy ->
        require(copy.keys.all { isKey(it) }) { "Configuration keys must be lowercase ASCII identifiers (1..128 characters)" }
    }

    val size: Int get() = values.size

    fun contains(key: String): Boolean = values.containsKey(key)
    fun stringValue(key: String): String? = values[key]

    /** Only literal "true" and "false" are accepted. */
    fun booleanValue(key: String): Boolean? = values[key]?.let {
        when (it) {
            "true" -> true
            "false" -> false
            else -> throw ConfigValueException(key, "boolean")
        }
    }

    /** Decimal integer within the signed 64-bit range; no trimming or fractional coercion. */
    fun longValue(key: String): Long? = values[key]?.let {
        if (!LONG_PATTERN.matches(it)) throw ConfigValueException(key, "long")
        it.toLongOrNull() ?: throw ConfigValueException(key, "long")
    }

    /** Finite double only: NaN and infinities are invalid configuration. */
    fun doubleValue(key: String): Double? = values[key]?.let {
        // Fix a portable decimal grammar before invoking platform number parsers.
        if (!DOUBLE_PATTERN.matches(it)) throw ConfigValueException(key, "finite double")
        val parsed = it.toDoubleOrNull()
        if (parsed == null || !parsed.isFinite()) throw ConfigValueException(key, "finite double")
        parsed
    }

    /** Override selected keys. Neither snapshot changes; an empty string remains a value, not deletion. */
    fun overlay(overrides: ConfigSnapshot): ConfigSnapshot = ConfigSnapshot(values + overrides.values)

    /** Never include values or keys when a snapshot is interpolated into logs. */
    override fun toString(): String = "ConfigSnapshot(size=$size)"

    companion object {
        private val LONG_PATTERN = Regex("[+-]?[0-9]+")
        private val DOUBLE_PATTERN = Regex("[+-]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)(?:[eE][+-]?[0-9]+)?")
        val Empty: ConfigSnapshot = ConfigSnapshot(emptyMap())

        private fun isKey(key: String): Boolean =
            key.length in 1..128 && key[0] in 'a'..'z' && key.all {
                it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '-' || it == '_'
            }
    }
}
