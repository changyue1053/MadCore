@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class, kotlinx.cinterop.ExperimentalForeignApi::class)
package com.mad.core

import com.mad.core.json.MiniJson
import com.mad.core.time.SystemClock
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.readBytes

/** Versioned primitive-only C boundary. No Kotlin object ownership crosses the ABI. */
@CName("madcore_abi_version")
fun madcoreAbiVersion(): Int = 1

@CName("madcore_epoch_millis")
fun madcoreEpochMillis(): Long = SystemClock.epochMillis()

/** -1 invalid buffer/UTF-8; 0 invalid object JSON; 1 valid object JSON. Max 64 KiB. */
@CName("madcore_json_object_valid")
fun madcoreJsonObjectValid(bytes: CPointer<ByteVar>?, length: Int): Int {
    if (bytes == null || length !in 1..65536) return -1
    return try {
        val input = bytes.readBytes(length).decodeToString(throwOnInvalidSequence = true)
        if (MiniJson.parseObject(input) != null) 1 else 0
    } catch (_: Exception) { -1 }
}
