package com.nuum.storage

import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import org.json.JSONException
import org.json.JSONObject

/**
 * Append-only JSONL. A last line without a trailing `\n` is an uncommitted append:
 * it is truncated away, and earlier complete lines stay.
 */
internal object JsonlFiles {
    fun repairTrailingPartialLine(file: File) {
        if (!file.isFile) return
        RandomAccessFile(file, "rw").use { raf ->
            val size = raf.length()
            if (size == 0L) return
            raf.seek(size - 1)
            if (raf.readByte() == NEWLINE) return
            var position = size - 1
            val buffer = ByteArray(SCAN_CHUNK)
            var newlineAt = -1L
            while (position > 0) {
                val start = maxOf(0L, position - buffer.size)
                val length = (position - start).toInt()
                raf.seek(start)
                raf.readFully(buffer, 0, length)
                var found = -1
                for (index in length - 1 downTo 0) {
                    if (buffer[index] == NEWLINE) {
                        found = index
                        break
                    }
                }
                if (found >= 0) {
                    newlineAt = start + found
                    break
                }
                position = start
            }
            raf.setLength(if (newlineAt >= 0) newlineAt + 1 else 0L)
        }
    }

    fun readLines(file: File): List<String> {
        repairTrailingPartialLine(file)
        if (!file.isFile || file.length() == 0L) return emptyList()
        return file.readText(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() }
    }

    fun appendLine(file: File, line: String) {
        file.parentFile?.mkdirs()
        repairTrailingPartialLine(file)
        FileOutputStream(file, true).use { out ->
            out.write(line.toByteArray(Charsets.UTF_8))
            out.write(NEWLINE.toInt())
            out.fd.sync()
        }
    }

    fun readTail(file: File, maxBytes: Int): String {
        repairTrailingPartialLine(file)
        if (!file.isFile || maxBytes <= 0 || file.length() == 0L) return ""
        return String(tailBytes(file, maxBytes), Charsets.UTF_8)
    }

    /** createdAt of the last JSON object in the tail window, or 0 when there is none. */
    fun lastCreatedAt(file: File): Long {
        repairTrailingPartialLine(file)
        if (!file.isFile || file.length() == 0L) return 0L
        val text = String(tailBytes(file, StoragePaths.TAIL_WINDOW_BYTES), Charsets.UTF_8)
        var last = 0L
        var seen = false
        for (line in text.split('\n')) {
            if (line.isEmpty()) continue
            val created = createdAt(line) ?: continue
            last = created
            seen = true
        }
        return if (seen) last else 0L
    }

    private fun tailBytes(file: File, maxBytes: Int): ByteArray {
        RandomAccessFile(file, "r").use { raf ->
            val size = raf.length()
            if (size == 0L) return ByteArray(0)
            val length = minOf(size, maxBytes.toLong()).toInt()
            val start = size - length
            val startsAtLine = start == 0L || run {
                raf.seek(start - 1)
                raf.readByte() == NEWLINE
            }
            raf.seek(start)
            val bytes = ByteArray(length)
            raf.readFully(bytes)
            if (startsAtLine) return bytes
            val newline = bytes.indexOfFirst { it == NEWLINE }
            if (newline < 0 || newline == bytes.lastIndex) return ByteArray(0)
            return bytes.copyOfRange(newline + 1, bytes.size)
        }
    }

    private fun createdAt(line: String): Long? {
        val json = try {
            JSONObject(line)
        } catch (_: JSONException) {
            return null
        }
        if (!json.has("createdAt") || json.isNull("createdAt")) return null
        val value = json.opt("createdAt")
        return if (value is Number) value.toLong() else null
    }

    private const val SCAN_CHUNK = 8192
    private const val NEWLINE = '\n'.code.toByte()
}
