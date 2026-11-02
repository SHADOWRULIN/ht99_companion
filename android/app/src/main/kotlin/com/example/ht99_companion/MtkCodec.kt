package com.example.ht99_companion

import java.io.ByteArrayOutputStream
import java.util.Calendar
import java.util.Date
import java.util.TimeZone

/**
 * Pure 64-bit Kotlin implementation of the MediaTek Wearable frame codec
 * reverse-engineered from libCommand.so and com.mediatek.wearable.w0.
 */
object MtkCodec {
    const val T_DATA = 1
    const val T_SYNC = 2
    const val T_ACKY = 3
    const val T_VERN = 4
    const val T_MAPX = 5
    const val T_MAPD = 6
    const val T_CAPC = 7
    const val T_MREE = 8
    const val T_EXCD = 9

    private val MAGIC = mapOf(
        1 to "DATA",
        2 to "SYNC",
        3 to "ACKY",
        4 to "VERN",
        5 to "MAPX",
        6 to "MAPD",
        7 to "CAPC",
        8 to "MREE",
        9 to "EXCD"
    )

    private val MAGIC_REV = MAGIC.entries.associate { it.value to it.key }

    // Exact 130-byte RC4 key from libCommand.so (including trailing NUL byte)
    private val KEY: ByteArray = (
        "we had everything before us, we had nothing before us, we were all going direct to Heaven, we were all going direct the other way"
    ).toByteArray(Charsets.ISO_8859_1) + byteArrayOf(0)

    /**
     * Standard RC4 cipher using the 130-byte MediaTek key.
     * Calling rc4() on plaintext encrypts it; calling rc4() on ciphertext decrypts it.
     */
    fun rc4(data: ByteArray): ByteArray {
        val s = IntArray(256) { it }
        var j = 0
        for (i in 0 until 256) {
            j = (j + s[i] + (KEY[i % KEY.size].toInt() and 0xFF)) and 0xFF
            val t = s[i]
            s[i] = s[j]
            s[j] = t
        }
        val out = ByteArray(data.size)
        var a = 0
        var b = 0
        for (k in data.indices) {
            a = (a + 1) and 0xFF
            b = (b + s[a]) and 0xFF
            val t = s[a]
            s[a] = s[b]
            s[b] = t
            val xorByte = s[(s[a] + s[b]) and 0xFF]
            out[k] = ((data[k].toInt() and 0xFF) xor xorByte).toByte()
        }
        return out
    }

    /**
     * Equivalent to LoadJniFunction.getDataCmdFromJni(type, cmdHeader).
     * Prepends the 4-char magic + space, RC4-encrypts the command header,
     * and wraps it with 0xF0F0F0F1 + 4-byte Big-Endian length.
     */
    fun encodeHeader(type: Int, cmdHeader: String): ByteArray {
        val magic = MAGIC[type] ?: "EXCD"
        val plainHeader = "$magic $cmdHeader".toByteArray(Charsets.UTF_8)
        val encryptedHeader = rc4(plainHeader)
        val len = encryptedHeader.size
        return byteArrayOf(
            0xF0.toByte(),
            0xF0.toByte(),
            0xF0.toByte(),
            0xF1.toByte(),
            ((len shr 24) and 0xFF).toByte(),
            ((len shr 16) and 0xFF).toByte(),
            ((len shr 8) and 0xFF).toByte(),
            (len and 0xFF).toByte()
        ) + encryptedHeader
    }

    /**
     * Encodes a complete frame (encrypted header + raw payload bytes).
     */
    fun encodePacket(type: Int, cmdHeader: String, payload: ByteArray = ByteArray(0)): ByteArray {
        return encodeHeader(type, cmdHeader) + payload
    }

    /**
     * Encodes an EXCD "WW ww 0 0 <len> " command with its ASCII payload.
     */
    fun encodeWw(cmd: String): ByteArray {
        val body = cmd.toByteArray(Charsets.UTF_8)
        val header = "WW ww 0 0 ${body.size} "
        return encodePacket(T_EXCD, header, body)
    }

    /**
     * Encodes a KCT_PEDOMETER command under EXCD.
     */
    fun encodePedometer(cmd: String = "GET,0"): ByteArray {
        val body = cmd.toByteArray(Charsets.UTF_8)
        val header = "KCT_PEDOMETER kct_pedometer 0 0 ${body.size} "
        return encodePacket(T_EXCD, header, body)
    }

    /**
     * Encodes a MediaTek SYNC time frame (matching w0.i() in WWfit).
     */
    fun encodeSyncTime(is24Hour: Boolean, useNewFormat: Boolean = false): ByteArray {
        val nowMs = System.currentTimeMillis()
        val cal = Calendar.getInstance()
        cal.timeInMillis = nowMs
        val utcSec = (cal.timeInMillis / 1000L).toInt()
        val tz = TimeZone.getDefault()
        var tzOffsetMs = tz.rawOffset
        if (tz.inDaylightTime(Date(nowMs))) {
            tzOffsetMs += tz.dstSavings
        }

        if (useNewFormat) {
            val bodyStr = "$utcSec $tzOffsetMs"
            val bodyBytes = bodyStr.toByteArray(Charsets.UTF_8)
            val header = "bnsrv_time mtk_bnapk 0 0 ${bodyBytes.size} "
            return encodePacket(T_EXCD, header, bodyBytes)
        }

        val formatFlag = if (is24Hour) "1" else "0"
        val syncStr = "$utcSec $tzOffsetMs $formatFlag"
        return encodeHeader(T_SYNC, syncStr)
    }

    /**
     * Encodes a MediaTek XML Notification packet under T_DATA (type 1).
     */
    fun encodeNotificationXml(
        msgId: Int,
        pkg: String,
        title: String,
        body: String,
        isCall: Boolean = false
    ): ByteArray {
        val timestampSec = (System.currentTimeMillis() / 1000L).toInt()
        val safeTitle = escapeXml(title.take(128))
        val safeBody = escapeXml(body.take(256))
        val safePkg = escapeXml(pkg)
        val category = if (isCall) "call" else "notification"
        val subType = if (isCall) "missed_call" else "text"

        val xml = buildString {
            append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
            append("<event_report>")
            append("<header>")
            append("<category>$category</category>")
            append("<subType>$subType</subType>")
            append("<msgId>$msgId</msgId>")
            append("<action>add</action>")
            append("</header>")
            append("<body>")
            append("<sender>$safeTitle</sender>")
            append("<appId>$safePkg</appId>")
            append("<title>$safeTitle</title>")
            append("<content>$safeBody</content>")
            append("<timestamp>$timestampSec</timestamp>")
            append("</body>")
            append("</event_report>")
        }
        val xmlBytes = xml.toByteArray(Charsets.UTF_8)
        return encodePacket(T_DATA, "${xmlBytes.size}", xmlBytes)
    }

    /**
     * Encodes Weather payload under EXCD yahooweather controller.
     */
    fun encodeWeather(city: String, conditionCode: Int, currentTemp: Int, highTemp: Int, lowTemp: Int): ByteArray {
        val safeCity = if (city.isBlank()) "Local" else city.trim().replace(" ", "_")
        val condName = when (conditionCode) {
            1 -> "Cloudy"
            2 -> "Rain"
            3 -> "Snow"
            else -> "Sunny"
        }
        val bodyStr = "$safeCity $condName $currentTemp $highTemp $lowTemp"
        val bodyBytes = bodyStr.toByteArray(Charsets.UTF_8)
        val header = "yahooweather smartwatch 0 0 ${bodyBytes.size} "
        return encodePacket(T_EXCD, header, bodyBytes)
    }

    private fun escapeXml(s: String): String {
        return s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }

    data class DecodedFrame(
        val cmdType: Int,
        val headerText: String,
        val payload: ByteArray
    ) {
        val payloadText: String get() = String(payload, Charsets.UTF_8)
    }

    /**
     * Stateful stream parser matching w0.java's runningReadFSM (states 0, 1, 2).
     */
    class StreamParser {
        private val buffer = ByteArrayOutputStream()

        fun reset() {
            buffer.reset()
        }

        fun feed(chunk: ByteArray): List<DecodedFrame> {
            if (chunk.isEmpty()) return emptyList()
            buffer.write(chunk)
            val out = mutableListOf<DecodedFrame>()

            while (true) {
                val bytes = buffer.toByteArray()
                if (bytes.size < 8) break

                // Locate F0 F0 F0 F1 magic signature
                var magicPos = -1
                for (i in 0..bytes.size - 4) {
                    if (bytes[i] == 0xF0.toByte() &&
                        bytes[i + 1] == 0xF0.toByte() &&
                        bytes[i + 2] == 0xF0.toByte() &&
                        bytes[i + 3] == 0xF1.toByte()
                    ) {
                        magicPos = i
                        break
                    }
                }

                if (magicPos == -1) {
                    // Fallback: Check if watch sent unframed ASCII directly
                    val text = String(bytes.filter { it in 32..126 }.toByteArray(), Charsets.UTF_8)
                    if (text.contains("WW ") || text.contains(",") || text.contains("ios indication")) {
                        out.add(DecodedFrame(T_EXCD, "RAW", bytes))
                    }
                    buffer.reset()
                    break
                }

                if (magicPos > 0) {
                    val remaining = bytes.copyOfRange(magicPos, bytes.size)
                    buffer.reset()
                    buffer.write(remaining)
                    continue
                }

                val cur = buffer.toByteArray()
                if (cur.size < 8) break

                val cmdLen = ((cur[4].toInt() and 0xFF) shl 24) or
                        ((cur[5].toInt() and 0xFF) shl 16) or
                        ((cur[6].toInt() and 0xFF) shl 8) or
                        (cur[7].toInt() and 0xFF)

                if (cmdLen <= 0 || cmdLen > 4096) {
                    val skip = cur.copyOfRange(4, cur.size)
                    buffer.reset()
                    buffer.write(skip)
                    continue
                }

                if (cur.size < 8 + cmdLen) break

                val encCmd = cur.copyOfRange(8, 8 + cmdLen)
                val decCmdBytes = rc4(encCmd)
                val decHeader = String(decCmdBytes, Charsets.UTF_8).trimEnd('\u0000', ' ')

                val tag = if (decHeader.length >= 4) decHeader.substring(0, 4) else ""
                val cmdType = MAGIC_REV[tag] ?: T_EXCD

                // Parse trailing data length from decrypted command header if present
                val parts = decHeader.split(" ").filter { it.isNotEmpty() }
                val dataLen = if (parts.size >= 2) {
                    parts.last().toIntOrNull()?.coerceIn(0, 51200) ?: 0
                } else {
                    0
                }

                if (cur.size < 8 + cmdLen + dataLen) {
                    // Wait for remaining payload bytes to arrive
                    break
                }

                val payload = if (dataLen > 0) {
                    cur.copyOfRange(8 + cmdLen, 8 + cmdLen + dataLen)
                } else {
                    ByteArray(0)
                }

                out.add(DecodedFrame(cmdType, decHeader, payload))

                val consumed = 8 + cmdLen + dataLen
                val rest = cur.copyOfRange(consumed, cur.size)
                buffer.reset()
                if (rest.isNotEmpty()) {
                    buffer.write(rest)
                }
            }
            return out
        }
    }
}