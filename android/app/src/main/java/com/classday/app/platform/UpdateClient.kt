package com.classday.app.platform

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.classday.app.core.ReleaseEntry
import com.classday.app.core.UpdateDecision
import com.classday.app.core.UpdateManifest
import com.classday.app.core.Versions
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

object UpdateClient {
    val current: String = com.classday.app.BuildConfig.VERSION_NAME

    fun check(context: Context): String {
        val manifest = try {
            http(UpdateManifest.manifestUrl)
        } catch (_: Exception) {
            return fallback(context, "更新列表暂时读不到")
        }
        val channel = try {
            UpdateManifest.parseAndroid(manifest)
        } catch (_: Exception) {
            null
        }
        if (channel == null) return fallback(context, "安卓通道还没有发布")
        return when (val decision = UpdateManifest.decision(channel, current)) {
            UpdateDecision.UpToDate -> "已是最新版 $current"
            is UpdateDecision.UpdateAvailable -> download(context, decision.release, decision.mandatory)
            is UpdateDecision.BelowMinimum -> download(context, decision.release, true)
            UpdateDecision.MissingChannel -> fallback(context, "安卓通道还没有发布")
        }
    }

    private fun fallback(context: Context, reason: String): String {
        val release = try {
            val json = JSONObject(http(UpdateManifest.githubLatest))
            val tag = json.optString("tag_name").removePrefix("v")
            val assets = json.optJSONArray("assets")
            var apk: String? = null
            if (assets != null) {
                for (index in 0 until assets.length()) {
                    val asset = assets.optJSONObject(index) ?: continue
                    val name = asset.optString("name")
                    if (name.endsWith(".apk")) apk = asset.optString("browser_download_url")
                }
            }
            if (!tag.isNullOrBlank() && Versions.compare(current, tag) < 0 && !apk.isNullOrBlank()) {
                download(context, ReleaseEntry(tag, "Classday-android-v$tag.apk", 1, "", apk, ""), false)
            } else {
                "$reason。当前 $current"
            }
        } catch (_: Exception) {
            "$reason。当前 $current"
        }
        return release
    }

    private fun download(context: Context, release: ReleaseEntry, mandatory: Boolean): String {
        if (release.downloadUrl.isBlank()) {
            return if (mandatory) "必须更新到 ${release.version}，但没有下载地址" else "发现 ${release.version}，还没有安装包"
        }
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(dir, release.file.ifBlank { "Classday-android-v${release.version}.apk" })
        val connection = URL(release.downloadUrl).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.inputStream.use { input -> file.outputStream().use { input.copyTo(it) } }
        if (release.sha256.length == 64) {
            val digest = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
            if (!digest.equals(release.sha256, ignoreCase = true)) {
                file.delete()
                return "更新包校验失败"
            }
        }
        val uri = FileProvider.getUriForFile(context, "com.classday.app.files", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
        return "正在安装 ${release.version}" + if (mandatory) "（必须更新）" else ""
    }

    private fun http(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.setRequestProperty("User-Agent", "Classday-Android/2.9.2")
        connection.connectTimeout = 15000
        connection.readTimeout = 20000
        return connection.inputStream.bufferedReader().readText()
    }
}
