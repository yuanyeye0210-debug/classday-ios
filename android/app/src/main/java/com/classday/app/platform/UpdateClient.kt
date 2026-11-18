package com.classday.app.platform

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.classday.app.core.ReleaseEntry
import com.classday.app.core.UpdateDecision
import com.classday.app.core.UpdateManifest
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object UpdateClient {
    val current: String = com.classday.app.BuildConfig.VERSION_NAME

    fun check(context: Context, manifestUrl: String = UpdateManifest.manifestUrl): String {
        val manifest = try { http(manifestUrl) } catch (error: SourceFailure) {
            return com.classday.app.core.UpdateIntegrity.failure(error.code)
        } catch (_: Exception) { return com.classday.app.core.UpdateIntegrity.failure(null) }
        val channel = try { UpdateManifest.parseAndroid(manifest) } catch (_: Exception) { null }
        if (channel == null) return "更新清单尚无可用安卓版本或内容无效，当前版本仍可使用"
        return when (val decision = UpdateManifest.decision(channel, current)) {
            UpdateDecision.UpToDate -> "已是最新版 $current"
            is UpdateDecision.UpdateAvailable -> download(context, decision.release, decision.mandatory)
            is UpdateDecision.BelowMinimum -> download(context, decision.release, true)
            UpdateDecision.MissingChannel -> "更新清单尚无可用安卓版本，当前版本仍可使用"
        }
    }

    private fun download(context: Context, release: ReleaseEntry, mandatory: Boolean): String {
        if (!com.classday.app.core.UpdateIntegrity.safe(release)) return "安装包信息不完整或不安全，请等待发布者修复"
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(dir, release.file)
        var connection: HttpURLConnection? = null
        val installed = try {
            com.classday.app.core.UpdatePackageStager.installVerified(release, file,
                source = {
                    val request = URL(release.downloadUrl).openConnection() as HttpURLConnection
                    connection = request
                    request.connectTimeout = 15000
                    request.readTimeout = 30000
                    require(request.responseCode in 200..299)
                    request.inputStream
                },
                install = { verified ->
                    val uri = FileProvider.getUriForFile(context, "com.classday.app.files", verified)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                })
        } finally { connection?.disconnect() }
        return if (installed) "正在安装 ${release.version}" + if (mandatory) "（必须更新）" else ""
            else "更新包下载、校验或安装启动未完成，请稍后重试"
    }

    private class SourceFailure(val code: Int) : Exception()
    private fun http(url: String): String {
        val source = java.net.URI(url)
        require(source.scheme == "https" && source.host != null && source.userInfo == null)
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.setRequestProperty("User-Agent", "Classday-Android/$current")
            connection.connectTimeout = 15000
            connection.readTimeout = 20000
            if (connection.responseCode !in 200..299) throw SourceFailure(connection.responseCode)
            return connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= 1024 * 1024)
                    output.write(buffer, 0, count)
                }
                output.toString("UTF-8")
            }
        } finally { connection.disconnect() }
    }
}
