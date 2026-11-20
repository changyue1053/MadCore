package com.mad.core.logging

import com.mad.core.time.Clock
import com.mad.core.time.SystemClock

/** Ordered from least to most severe. */
enum class LogLevel { Debug, Info, Warning, Error }

/** Callers must explicitly classify fields as public. No hashing or automatic PII detection. */
enum class FieldPrivacy { Public, Sensitive }

/** Stable domain/code identifiers, never a free-form message or exception stack trace. */
data class LogRecord(
    val level: LogLevel,
    val domain: String,
    val code: String,
    val fields: Map<String, String>,
    val epochMillis: Long,
)

/** Host adapter: immediate, non-blocking delivery. No storage, upload or thread dispatch is provided. */
interface LogSink {
    fun accept(record: LogRecord)

    companion object {
        val None: LogSink = object : LogSink {
            override fun accept(record: LogRecord) {}
        }
    }
}

/**
 * Platform-neutral structured logger. Sensitive records are dropped in ALL build variants.
 * Identifiers, credentials, user content and URL queries must not be marked Public.
 * Domain and code accept only short ASCII identifiers; fields still require caller review.
 *
 * Calls execute on the caller thread. Shared sinks and clocks must support concurrent calls.
 * Ordinary clock/sink Exceptions are isolated from business logic; fatal Errors are not swallowed.
 */
class StructuredLogger(
    private val sink: LogSink = LogSink.None,
    private val clock: Clock = SystemClock,
    private val minimumLevel: LogLevel = LogLevel.Info,
) {
    /** Returns true only when an eligible record was delivered without an Exception. */
    fun record(
        level: LogLevel,
        domain: String,
        code: String,
        fields: Map<String, String> = emptyMap(),
        privacy: FieldPrivacy = FieldPrivacy.Sensitive,
    ): Boolean {
        if (level < minimumLevel || privacy != FieldPrivacy.Public) return false
        if (!isIdentifier(domain) || !isIdentifier(code)) return false
        return try {
            // Copy before delivery: later mutations of the caller's map cannot alter a retained record.
            sink.accept(LogRecord(level, domain, code, fields.toMap(), clock.epochMillis()))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun isIdentifier(value: String): Boolean =
        value.isNotEmpty() && value.length <= 64 && value.all {
            it in 'a'..'z' || it in '0'..'9' || it == '.' || it == '-' || it == '_'
        }
}
