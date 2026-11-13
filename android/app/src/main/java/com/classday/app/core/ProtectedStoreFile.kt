package com.classday.app.core

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.ZoneOffset
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong

data class StoreLoadResult(val document: StoreDocument, val error: String? = null)

/** File operations shared by the app and widget; independent of Android for regression tests. */
class ProtectedStoreFile(
    private val file: File,
    private val maxBackups: Int = DEFAULT_MAX_BACKUPS,
    private val maxRecoveryFiles: Int = DEFAULT_MAX_RECOVERY_FILES
) {
    init {
        require(maxBackups >= 1) { "maxBackups must be at least 1" }
        require(maxRecoveryFiles >= 1) { "maxRecoveryFiles must be at least 1" }
    }

    fun load(): StoreLoadResult {
        return try {
            if (!file.exists()) {
                val demo = DemoData.makeDocument()
                save(demo)
                StoreLoadResult(demo)
            } else {
                val outcome = StoreCodec.importing(file.readText())
                val document = outcome.document
                if (document != null) StoreLoadResult(document)
                else {
                    preserveInvalidFile()
                    StoreLoadResult(DemoData.makeDocument(), "原课表无法读取，原文件和恢复副本已保留，已禁止覆盖。当前仅显示演示内容：${outcome.errors.joinToString("；")}")
                }
            }
        } catch (_: Exception) {
            StoreLoadResult(DemoData.makeDocument(), "无法读取或保全课表文件，未覆盖原文件。当前仅显示演示内容，请先恢复原数据后再编辑。")
        }
    }

    fun save(document: StoreDocument) {
        val report = StoreCodec.validate(document, CivilCalendar(ZoneOffset.UTC))
        check(report.isAcceptable) { "未保存：${report.errors.joinToString("；")}" }
        if (file.exists() && StoreCodec.importing(file.readText()).document == null) {
            preserveInvalidFile()
            error("原课表无法读取，已保留原文件与恢复副本，禁止覆盖；请先恢复原数据")
        }
        val parent = file.parentFile ?: File(".")
        parent.mkdirs()
        val backups = if (file.exists()) File(parent, "backups").apply { mkdirs() } else null
        val createdBackup = if (backups != null) {
            val stamp = nextTimestamp()
            File(backups, "classday-${"%016d".format(stamp)}-${UUID.randomUUID()}.json").also { backup ->
                file.copyTo(backup, overwrite = true)
                backup.setLastModified(stamp)
            }
        } else {
            null
        }
        val temporary = File(parent, "${file.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.writeText(StoreCodec.exporting(document))
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (err: Throwable) {
            temporary.delete()
            createdBackup?.delete()
            throw err
        }
        if (backups != null) {
            pruneDirectory(backups, prefix = "classday-", maxFiles = maxBackups)
        }
    }

    private fun preserveInvalidFile() {
        val bytes = file.readBytes()
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val parent = file.parentFile ?: File(".")
        val recovery = File(parent, "recovery").apply { mkdirs() }
        val copy = File(recovery, "classday-invalid-$digest.json")
        if (!copy.exists() || !copy.readBytes().contentEquals(bytes)) {
            copy.writeBytes(bytes)
        }
        check(copy.readBytes().contentEquals(bytes)) { "恢复副本校验失败" }
        copy.setLastModified(nextTimestamp())
        pruneDirectory(recovery, prefix = "classday-invalid-", maxFiles = maxRecoveryFiles, protectedFile = copy)
    }

    private fun pruneDirectory(
        directory: File,
        prefix: String,
        maxFiles: Int,
        protectedFile: File? = null
    ) {
        val candidates = directory.listFiles()
            ?.filter { it.isFile && it.name.startsWith(prefix) && it.name.endsWith(".json") }
            ?: return
        if (candidates.size <= maxFiles) return
        val sortedNewestFirst = candidates.sortedWith(
            compareByDescending<File> { it.lastModified() }
                .thenByDescending { backupStamp(it.name) ?: Long.MIN_VALUE }
                .thenByDescending { it.name }
        )
        val retained = linkedSetOf<File>()
        if (protectedFile != null && candidates.contains(protectedFile)) {
            retained.add(protectedFile)
        }
        for (candidate in sortedNewestFirst) {
            if (retained.size >= maxFiles) break
            retained.add(candidate)
        }
        for (candidate in sortedNewestFirst) {
            if (candidate !in retained) {
                candidate.delete()
            }
        }
    }

    companion object {
        const val DEFAULT_MAX_BACKUPS = 5
        const val DEFAULT_MAX_RECOVERY_FILES = 5

        private val STAMP_REGEX = Regex("""^classday-(\d{16})-""")
        private val lastTimestamp = AtomicLong(0L)

        private fun backupStamp(name: String): Long? =
            STAMP_REGEX.find(name)?.groupValues?.getOrNull(1)?.toLongOrNull()

        private fun nextTimestamp(): Long {
            while (true) {
                val now = System.currentTimeMillis()
                val last = lastTimestamp.get()
                val next = if (now >= last + 1000L) now else last + 1000L
                if (lastTimestamp.compareAndSet(last, next)) return next
            }
        }
    }
}
