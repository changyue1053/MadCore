package com.mad.core.net

import kotlin.test.Test

/** Host-only test of the exact Kotlin codec. No network or platform adapter. */
class CopiedHttpHeadersHostTest {
@Test fun codecBoundsAndValidation() {
    check(CopiedHttpHeaders.encode(emptyMap())!!.decodeToString() == "{}")
    check(CopiedHttpHeaders.encode(mapOf("X-Quote" to "a\"\\é"))!!.decodeToString() ==
        """{"X-Quote":"a\"\\é"}""")
    check(CopiedHttpHeaders.encode(mapOf("X-Exact" to "x".repeat(16_370)))!!.size == copiedHeaderCap)
    check(CopiedHttpHeaders.encode(mapOf("X-Exact" to "x".repeat(16_371))) == null)
    check(CopiedHttpHeaders.encode(mapOf("X-Multi" to "é".repeat(10_000))) == null)
    check(CopiedHttpHeaders.encode(mapOf("X-Control" to "bad\nvalue")) == null)
    check(CopiedHttpHeaders.encode(mapOf("X-Unicode" to "\uD800")) == null)
    check(CopiedHttpHeaders.decode("""{"Set-Cookie":["first=a,b","second=c"],"X-Value":["a\"b","\uD83D\uDE00"],"X-Empty":[]}""".encodeToByteArray()) ==
        linkedMapOf("Set-Cookie" to listOf("first=a,b", "second=c"), "X-Value" to listOf("a\"b", "😀"), "X-Empty" to emptyList()))
    val rejected = listOf(
        "", "{}", """{"X":"scalar"}""", """{"X":[null]}""", """{"X":[["nested"]]}""",
        """{"X":["ok"],"X":["duplicate"]}""", """{"Bad Name":["a"]}""",
        """{"X":["\uD800"]}""", """{"X":["\u000a"]}""", """{"X":["\u007f"]}""",
        """{"X":["\uFFFF","\uZZZZ"]}""", """{"X":["ok",]}""", "{} trailing",
        """{"X":["${"é".repeat(10_000)}"]}""")
    rejected.filter { it != "{}" }.forEach {
        check(runCatching { CopiedHttpHeaders.decode(it.encodeToByteArray()) }.isFailure)
    }
    check(runCatching { CopiedHttpHeaders.decode(byteArrayOf(0xc0.toByte(), 0x80.toByte())) }.isFailure)
    println("Copied HTTP Kotlin header codec: round trips, bounds and malformed inputs passed")
}

}
