package com.classday.app.core

import java.io.File
import java.util.UUID

/** Only files created for this camera flow may be resolved or removed. */
object CameraCaptureFiles {
    private val ownedName = Regex("capture-[0-9a-fA-F-]{36}\\.jpg")
    const val maxBytes = 16L * 1024 * 1024
    const val retentionMillis = 24L * 60 * 60 * 1000

    /** Retry interrupted cleanup on the next visit to the import screen, never recursively. */
    fun removeExpired(directory: File, protectedNames: Set<String>, nowMillis: Long): Int {
        if (nowMillis < retentionMillis) return 0
        val cutoff = nowMillis - retentionMillis
        var removed = 0
        for (entry in directory.listFiles().orEmpty()) {
            if (entry.name in protectedNames) continue
            // Filesystem errors must not prevent importing; a later visit retries them.
            runCatching {
                val file = resolve(directory, entry.name) ?: return@runCatching
                val modified = file.lastModified()
                if (file.isFile && modified > 0 && modified <= cutoff && remove(directory, file.name)) removed++
            }
        }
        return removed
    }

    fun create(directory: File): File {
        require(directory.isDirectory || directory.mkdirs()) { "无法创建拍照目录" }
        val file = File(directory, "capture-${UUID.randomUUID()}.jpg")
        check(file.createNewFile()) { "无法准备照片文件" }
        return file
    }

    fun resolve(directory: File, name: String?): File? {
        if (name == null || !ownedName.matches(name)) return null
        val candidate = File(directory, name)
        return if (candidate.canonicalFile.parentFile == directory.canonicalFile) candidate else null
    }

    fun readablePhoto(file: File) = file.isFile && file.length() in 1..maxBytes

    fun remove(directory: File, name: String?): Boolean {
        val file = resolve(directory, name) ?: return false
        return !file.exists() || file.delete()
    }
}
