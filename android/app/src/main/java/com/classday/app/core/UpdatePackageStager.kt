package com.classday.app.core

import java.io.File
import java.io.InputStream
import java.security.MessageDigest

/** The actual download-to-install gate; adapters supply HTTP and the installer. */
object UpdatePackageStager {
    fun installVerified(release: ReleaseEntry, target: File,
                        source: () -> InputStream, install: (File) -> Unit): Boolean {
        if (!UpdateIntegrity.safe(release) || target.name != release.file) return false
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            var count = 0L
            source().use { input -> target.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    count += read
                    require(count <= release.size)
                    digest.update(buffer, 0, read)
                    output.write(buffer, 0, read)
                }
            } }
            val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
            require(UpdateIntegrity.matches(release, count, hash))
            install(target)
            true
        } catch (_: Exception) {
            target.delete()
            false
        }
    }
}
