package com.mad.core.net

internal const val copiedHeaderCap = 16_384

/** Strict, bounded wire subset: request string values, response string arrays. */
internal object CopiedHttpHeaders {
    fun encode(values: Map<String, String>): ByteArray? {
        val out = StringBuilder()
        fun put(c: Char) {
            require(out.length < copiedHeaderCap)
            out.append(c)
        }
        fun quote(value: String) {
            put('"')
            for (c in value) {
                if (c == '"' || c == '\\') put('\\')
                require(c >= ' ' && c != '\u007f')
                put(c)
            }
            put('"')
        }
        return try {
            put('{')
            for ((name, value) in values) {
                if (out.length > 1) put(',')
                quote(name)
                put(':')
                quote(value)
            }
            put('}')
            out.toString().encodeToByteArray(throwOnInvalidSequence = true)
                .takeIf { it.size <= copiedHeaderCap }
        } catch (_: Exception) { null }
    }

    fun decode(bytes: ByteArray): Map<String, List<String>> {
        require(bytes.size in 1..copiedHeaderCap)
        return Reader(bytes.decodeToString(throwOnInvalidSequence = true)).read()
    }

    private class Reader(private val text: String) {
        private var pos = 0
        private fun white() {
            while (pos < text.length && text[pos] in " \t\r\n") pos++
        }
        private fun take(c: Char): Boolean {
            white()
            if (pos >= text.length || text[pos] != c) return false
            pos++
            return true
        }
        private fun need(c: Char) { require(take(c)) }
        private fun string(): String {
            need('"')
            val out = StringBuilder()
            while (pos < text.length) {
                val c = text[pos++]
                when (c) {
                    '"' -> return out.toString()
                    '\\' -> {
                        require(pos < text.length)
                        val escaped = text[pos++]
                        out.append(when (escaped) {
                            '"', '\\', '/' -> escaped
                            'b' -> '\b'
                            'f' -> '\u000c'
                            'n' -> '\n'
                            'r' -> '\r'
                            't' -> '\t'
                            'u' -> {
                                require(pos + 4 <= text.length)
                                var code = 0
                                repeat(4) {
                                    val digit = text[pos++]
                                    require(digit in '0'..'9' || digit in 'a'..'f' || digit in 'A'..'F')
                                    code = code * 16 + digit.digitToInt(16)
                                }
                                code.toChar()
                            }
                            else -> throw IllegalArgumentException("Invalid header JSON escape")
                        })
                    }
                    else -> { require(c >= ' '); out.append(c) }
                }
            }
            throw IllegalArgumentException("Invalid header JSON string")
        }

        fun read(): Map<String, List<String>> {
            need('{')
            val result = linkedMapOf<String, List<String>>()
            if (!take('}')) {
                do {
                    val key = string()
                    require(key.isNotEmpty() && key.all {
                        it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it in "!#$%&'*+-.^`_|~"
                    })
                    require(key !in result)
                    need(':')
                    need('[')
                    val values = mutableListOf<String>()
                    if (!take(']')) {
                        do {
                            val value = string()
                            require(value.none { it < ' ' && it != '\t' || it == '\u007f' })
                            // Reject lone escaped surrogates instead of silently replacing them.
                            value.encodeToByteArray(throwOnInvalidSequence = true)
                            values.add(value)
                        } while (take(','))
                        need(']')
                    }
                    result[key] = values
                } while (take(','))
                need('}')
            }
            white()
            require(pos == text.length)
            return result
        }
    }
}
