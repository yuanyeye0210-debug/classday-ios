package com.classday.app.core

import java.net.URI

object UpdateIntegrity {
    fun safe(release: ReleaseEntry): Boolean = runCatching {
        val uri = URI(release.downloadUrl)
        release.size > 0 && release.sha256.matches(Regex("[0-9a-fA-F]{64}")) &&
            release.file.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]*\\.apk")) &&
            uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null
    }.getOrDefault(false)
    fun matches(release: ReleaseEntry, bytes: Long, digest: String) =
        safe(release) && bytes == release.size && digest.equals(release.sha256, ignoreCase = true)
    fun failure(code: Int?): String = when (code) {
        404 -> "更新清单尚未发布，当前版本仍可使用"
        401, 403 -> "更新源暂不能公开读取，请等待发布者修复"
        null -> "暂时无法连接更新源，请检查网络后重试"
        else -> "暂时无法读取更新清单，请稍后重试"
    }
}
