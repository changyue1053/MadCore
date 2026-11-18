package com.mad.core.logging

import com.mad.core.testkit.ManualClock
import com.mad.core.time.Clock
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StructuredLoggerTest {
    private class RecordingSink : LogSink {
        val records = mutableListOf<LogRecord>()
        override fun accept(record: LogRecord) { records.add(record) }
    }

    @Test fun publicRecordUsesInjectedClockAndCopiesFields() {
        val sink = RecordingSink()
        val clock = ManualClock(100)
        clock.advanceMillis(10)
        val logger = StructuredLogger(sink, clock)
        val fields = mutableMapOf("status" to "ok")
        assertTrue(logger.record(LogLevel.Info, "core.net", "complete", fields, FieldPrivacy.Public))
        fields["status"] = "changed"
        assertEquals("ok", sink.records.single().fields["status"])
        assertEquals(110L, sink.records.single().epochMillis)
    }

    @Test fun defaultAndExplicitSensitiveRecordsAreDropped() {
        val sink = RecordingSink()
        val logger = StructuredLogger(sink)
        assertFalse(logger.record(LogLevel.Error, "core.auth", "failed", mapOf("secret" to "test-only")))
        assertFalse(logger.record(LogLevel.Error, "core.auth", "failed", privacy = FieldPrivacy.Sensitive))
        assertEquals(0, sink.records.size)
    }

    @Test fun thresholdIncludesExactBoundary() {
        val sink = RecordingSink()
        val logger = StructuredLogger(sink, minimumLevel = LogLevel.Warning)
        for (level in LogLevel.entries) {
            assertEquals(level >= LogLevel.Warning, logger.record(level, "core", "check", privacy = FieldPrivacy.Public))
        }
        assertEquals(listOf(LogLevel.Warning, LogLevel.Error), sink.records.map { it.level })
    }

    @Test fun invalidIdentifiersNeverReachSink() {
        val sink = RecordingSink()
        val logger = StructuredLogger(sink)
        for (invalid in listOf("", "free text", "url?token=example", "bad\nline", "a".repeat(65))) {
            assertFalse(logger.record(LogLevel.Info, invalid, "valid", privacy = FieldPrivacy.Public))
            assertFalse(logger.record(LogLevel.Info, "valid", invalid, privacy = FieldPrivacy.Public))
        }
        assertEquals(0, sink.records.size)
    }

    @Test fun ordinarySinkFailureIsIsolated() {
        val sink = object : LogSink { override fun accept(record: LogRecord) { error("test sink failure") } }
        assertFalse(StructuredLogger(sink).record(LogLevel.Info, "core", "check", privacy = FieldPrivacy.Public))
    }

    @Test fun rejectedRecordsDoNotReadClock() {
        var reads = 0
        val clock = object : Clock {
            override fun epochMillis(): Long { reads++; return 0L }
            override fun elapsedNanos(): Long { reads++; return 0L }
        }
        val sink = RecordingSink()
        val logger = StructuredLogger(sink, clock)
        assertFalse(logger.record(LogLevel.Info, "core", "sensitive"))
        assertFalse(logger.record(LogLevel.Debug, "core", "filtered", privacy = FieldPrivacy.Public))
        assertFalse(logger.record(LogLevel.Info, "invalid space", "check", privacy = FieldPrivacy.Public))
        assertEquals(0, reads)
        assertEquals(0, sink.records.size)
    }

    @Test fun fatalSinkErrorPropagates() {
        val sink = object : LogSink { override fun accept(record: LogRecord) { throw AssertionError("fatal test") } }
        assertFailsWith<AssertionError> {
            StructuredLogger(sink).record(LogLevel.Info, "core", "check", privacy = FieldPrivacy.Public)
        }
    }

    @Test fun ordinaryClockFailureIsIsolated() {
        val clock = object : Clock {
            override fun epochMillis(): Long = error("clock failure")
            override fun elapsedNanos(): Long = 0L
        }
        val sink = RecordingSink()
        assertFalse(StructuredLogger(sink, clock).record(LogLevel.Info, "core", "check", privacy = FieldPrivacy.Public))
        assertEquals(0, sink.records.size)
    }
}
