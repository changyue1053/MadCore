package com.mad.core.json

/**
 * 最小 JSON 对象解析（A ② 先落 core-upgrade，D2 提为 L1 公共面；I-E-01 反馈 ②）：
 * L1 不带 kotlinx-serialization，平坦 JSON（`/upgrade/check` 五字段、端智能结构化输出）手写一个够用的递归下降解析器。
 * 需要的模块依赖 `:core:core-json` 共用本对象，禁止复制副本。
 *
 * 覆盖：对象 / 数组 / 字符串（含 `\" \\ \/ \b \f \n \r \t \uXXXX` 转义，代理对按两个 `\u` 原样拼接）/ 数字（整数落 [Long]，带小数或指数落 [Double]）/
 * `true` / `false` / `null`；顶层必须是对象；尾部只许空白；嵌套深度上限 [MAX_DEPTH]。任何语法错误返回 null，不抛——调用方按"响应解不出"收口。
 * 值类型：`String` / `Long` / `Double` / `Boolean` / `null` / `Map<String, Any?>` / `List<Any?>`。
 */
object MiniJson {

    private const val MAX_DEPTH = 32

    /** 解析一个 JSON 对象；非对象、语法错误、超深返回 null。 */
    fun parseObject(text: String): Map<String, Any?>? {
        val parser = Parser(text)
        return try {
            parser.skipWhitespace()
            val value = parser.parseValue(depth = 0) as? Map<*, *> ?: return null
            parser.skipWhitespace()
            if (!parser.isAtEnd) return null
            @Suppress("UNCHECKED_CAST")
            value as Map<String, Any?>
        } catch (malformed: MalformedJson) {
            null
        }
    }

    private class MalformedJson : RuntimeException()

    private class Parser(private val text: String) {
        private var index = 0

        val isAtEnd: Boolean get() = index >= text.length

        fun skipWhitespace() {
            while (index < text.length && text[index].let { it == ' ' || it == '\n' || it == '\r' || it == '\t' }) index++
        }

        private fun peek(): Char = if (index < text.length) text[index] else throw MalformedJson()

        private fun expect(char: Char) {
            if (peek() != char) throw MalformedJson()
            index++
        }

        fun parseValue(depth: Int): Any? {
            if (depth > MAX_DEPTH) throw MalformedJson()
            skipWhitespace()
            return when (val c = peek()) {
                '{' -> parseObject(depth)
                '[' -> parseArray(depth)
                '"' -> parseString()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> if (c == '-' || c in '0'..'9') parseNumber() else throw MalformedJson()
            }
        }

        private fun literal(word: String, value: Any?): Any? {
            if (!text.startsWith(word, index)) throw MalformedJson()
            index += word.length
            return value
        }

        private fun parseObject(depth: Int): Map<String, Any?> {
            expect('{')
            val result = LinkedHashMap<String, Any?>()
            skipWhitespace()
            if (peek() == '}') {
                index++
                return result
            }
            while (true) {
                skipWhitespace()
                val key = parseString()
                skipWhitespace()
                expect(':')
                result[key] = parseValue(depth + 1)
                skipWhitespace()
                when (peek()) {
                    ',' -> index++
                    '}' -> {
                        index++
                        return result
                    }
                    else -> throw MalformedJson()
                }
            }
        }

        private fun parseArray(depth: Int): List<Any?> {
            expect('[')
            val result = ArrayList<Any?>()
            skipWhitespace()
            if (peek() == ']') {
                index++
                return result
            }
            while (true) {
                result.add(parseValue(depth + 1))
                skipWhitespace()
                when (peek()) {
                    ',' -> index++
                    ']' -> {
                        index++
                        return result
                    }
                    else -> throw MalformedJson()
                }
            }
        }

        private fun parseString(): String {
            expect('"')
            val builder = StringBuilder()
            while (true) {
                val c = peek()
                index++
                when (c) {
                    '"' -> return builder.toString()
                    '\\' -> {
                        val escaped = peek()
                        index++
                        when (escaped) {
                            '"' -> builder.append('"')
                            '\\' -> builder.append('\\')
                            '/' -> builder.append('/')
                            'b' -> builder.append('\b')
                            'f' -> builder.append('\u000C')
                            'n' -> builder.append('\n')
                            'r' -> builder.append('\r')
                            't' -> builder.append('\t')
                            'u' -> {
                                if (index + 4 > text.length) throw MalformedJson()
                                val code = text.substring(index, index + 4).toIntOrNull(16) ?: throw MalformedJson()
                                builder.append(code.toChar())
                                index += 4
                            }
                            else -> throw MalformedJson()
                        }
                    }
                    else -> {
                        if (c < ' ') throw MalformedJson() // 控制字符必须转义
                        builder.append(c)
                    }
                }
            }
        }

        private fun parseNumber(): Any {
            val start = index
            if (peek() == '-') index++
            if (peek() == '0') {
                index++
            } else {
                if (peek() !in '1'..'9') throw MalformedJson()
                while (index < text.length && text[index] in '0'..'9') index++
            }
            var isIntegral = true
            if (index < text.length && text[index] == '.') {
                isIntegral = false
                index++
                if (peek() !in '0'..'9') throw MalformedJson()
                while (index < text.length && text[index] in '0'..'9') index++
            }
            if (index < text.length && (text[index] == 'e' || text[index] == 'E')) {
                isIntegral = false
                index++
                if (peek() == '+' || peek() == '-') index++
                if (peek() !in '0'..'9') throw MalformedJson()
                while (index < text.length && text[index] in '0'..'9') index++
            }
            val literal = text.substring(start, index)
            return if (isIntegral) {
                literal.toLongOrNull() ?: literal.toDouble()
            } else {
                literal.toDoubleOrNull() ?: throw MalformedJson()
            }
        }
    }
}
