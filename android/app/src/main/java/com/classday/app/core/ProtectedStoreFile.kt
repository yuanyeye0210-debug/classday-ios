package com.classday.app.core

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.ZoneOffset
import java.util.UUID

data class StoreLoadResult(val document: StoreDocument, val error: String? = null)

/** File operations shared by the app and widget; independent of Android for regression tests. */
class ProtectedStoreFile(private val file: File) {
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
        file.parentFile.mkdirs()
        if (file.exists()) {
            val backups = File(file.parentFile, "backups").apply { mkdirs() }
            file.copyTo(File(backups, "classday-${UUID.randomUUID()}.json"))
        }
        val temporary = File(file.parentFile, "${file.name}.${UUID.randomUUID()}.tmp")
        temporary.writeText(StoreCodec.exporting(document))
        Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    private fun preserveInvalidFile() {
        val bytes = file.readBytes()
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val recovery = File(file.parentFile, "recovery").apply { mkdirs() }
        val copy = File(recovery, "classday-invalid-$digest.json")
        if (!copy.exists()) copy.writeBytes(bytes)
        check(copy.readBytes().contentEquals(bytes)) { "恢复副本校验失败" }
    }
}
