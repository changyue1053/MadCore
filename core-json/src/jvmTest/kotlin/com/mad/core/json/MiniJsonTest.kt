package com.mad.core.json

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class MiniJsonTest {

    @Test
    fun parsesUpgradeResponseShape() {
        val json = MiniJson.parseObject(
            """
            {
              "version": "1.2.3",
              "notes": "修复若干问题\n换行 \"引号\" \u4e2d\u6587 \\ / \t",
              "downloadUrl": "https://example.invalid/app-1.2.3.apk?x=1&y=2",
              "forced": false,
              "publishedAt": 1725000000000,
              "extra": null,
              "ratio": -1.5e2,
              "tags": ["a", 1, true, null, {"k": []}]
            }
            """.trimIndent(),
        )
        assertNotNull(json)
        assertEquals("1.2.3", json["version"])
        assertEquals("修复若干问题\n换行 \"引号\" 中文 \\ / \t", json["notes"])
        assertEquals("https://example.invalid/app-1.2.3.apk?x=1&y=2", json["downloadUrl"])
        assertEquals(false, json["forced"])
        assertEquals(1725000000000L, json["publishedAt"])
        assertNull(json["extra"])
        assertEquals(true, json.containsKey("extra"))
        assertEquals(-150.0, json["ratio"])
        assertEquals(listOf("a", 1L, true, null, mapOf("k" to emptyList<Any?>())), json["tags"])
        assertEquals(
            listOf("version", "notes", "downloadUrl", "forced", "publishedAt", "extra", "ratio", "tags"),
            json.keys.toList(),
        )
    }

    @Test
    fun emptyAndWhitespaceObjectsParse() {
        assertEquals(emptyMap<String, Any?>(), MiniJson.parseObject("{}"))
        assertEquals(emptyMap<String, Any?>(), MiniJson.parseObject(" \n\t{ } \r\n"))
        assertEquals(mapOf("a" to emptyMap<String, Any?>()), MiniJson.parseObject("""{"a":{}}"""))
    }

    @Test
    fun numbersLandOnLongOrDouble() {
        val json = MiniJson.parseObject("""{"i":0,"n":-7,"big":9223372036854775807,"huge":92233720368547758070,"f":1.0,"e":2E3}""")
        assertNotNull(json)
        assertEquals(0L, json["i"])
        assertEquals(-7L, json["n"])
        assertEquals(Long.MAX_VALUE, json["big"])
        assertEquals(9.223372036854776E19, json["huge"])
        assertEquals(1.0, json["f"])
        assertEquals(2000.0, json["e"])
    }

    @Test
    fun malformedInputReturnsNull() {
        val bad = listOf(
            "",
            "   ",
            "null",
            "\"string\"",
            "[1,2]",
            "{",
            "{\"a\"}",
            "{\"a\":}",
            "{\"a\":1,}",
            "{a:1}",
            "{'a':1}",
            "{\"a\":01}",
            "{\"a\":1.}",
            "{\"a\":-}",
            "{\"a\":tru}",
            "{\"a\":\"unterminated}",
            "{\"a\":\"bad \\x escape\"}",
            "{\"a\":\"\\u12\"}",
            "{\"a\":\"raw\nnewline\"}",
            "{\"a\":1} trailing",
            "{\"a\":1}}",
        )
        for (text in bad) {
            assertNull(MiniJson.parseObject(text), "应当解析失败：$text")
        }
    }

    @Test
    fun depthIsBounded() {
        val shallow = "{\"a\":" + "[".repeat(20) + "]".repeat(20) + "}"
        assertNotNull(MiniJson.parseObject(shallow))
        val deep = "{\"a\":" + "[".repeat(100) + "]".repeat(100) + "}"
        assertNull(MiniJson.parseObject(deep))
    }

    @Test
    fun duplicateKeysLastWins() {
        assertEquals(mapOf("a" to 2L), MiniJson.parseObject("""{"a":1,"a":2}"""))
    }
}
