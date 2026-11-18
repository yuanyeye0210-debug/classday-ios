package com.classday.app

import com.classday.app.core.*
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class UpdatePackageStagerTest {
    private val directory = Files.createTempDirectory("classday-update-test").toFile()
    private val target = File(directory, "app.apk")
    private val bytes = "a verified package".toByteArray()
    private val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    private val release = ReleaseEntry("2.9.5", target.name, bytes.size.toLong(), hash, "https://example.invalid/app.apk", "2026-11-15")
    @After fun cleanup() { directory.deleteRecursively() }
    @Test fun onlyVerifiedCompleteBytesReachInstallerAndSourceIsClosed() {
        var closed = false
        var calls = 0
        val source = object : ByteArrayInputStream(bytes) { override fun close() { closed = true; super.close() } }
        assertTrue(UpdatePackageStager.installVerified(release, target, { source }) { file ->
            calls++
            assertArrayEquals(bytes, file.readBytes())
        })
        assertTrue(closed)
        assertEquals(1, calls)
        assertTrue(target.exists())
    }
    @Test fun shortLongAndWrongDigestNeverInstallAndRemovePartialFile() {
        for ((metadata, content) in listOf(release to bytes.copyOf(bytes.size - 1),
                release to (bytes + byteArrayOf(1)), release.copy(sha256 = "0".repeat(64)) to bytes)) {
            var called = false
            assertFalse(UpdatePackageStager.installVerified(metadata, target, { ByteArrayInputStream(content) }) { called = true })
            assertFalse(called)
            assertFalse(target.exists())
        }
    }
    @Test fun connectionFailureNeverInstallsOrLeavesCachedFile() {
        target.writeText("old partial")
        var called = false
        assertFalse(UpdatePackageStager.installVerified(release, target, { throw IOException("connection failed") }) { called = true })
        assertFalse(called)
        assertFalse(target.exists())
    }
    @Test fun interruptedReadClosesSourceAndDeletesPartialBytes() {
        var closed = false
        var called = false
        val source = object : InputStream() {
            var reads = 0
            override fun read(): Int { if (reads++ > 3) throw IOException("interrupted"); return 1 }
            override fun close() { closed = true }
        }
        assertFalse(UpdatePackageStager.installVerified(release, target, { source }) { called = true })
        assertFalse(called)
        assertTrue(closed)
        assertFalse(target.exists())
    }
    @Test fun invalidMetadataDoesNotFetchOrInstallAndKeepsUnrelatedFiles() {
        val unrelated = File(directory, "keep.txt").apply { writeText("keep") }
        assertFalse(UpdatePackageStager.installVerified(release.copy(file = "../app.apk"), target,
            { error("must not fetch") }, { error("must not install") }))
        assertEquals("keep", unrelated.readText())
    }
    @Test fun installerFailureIsReportedAndCacheIsCleaned() {
        assertFalse(UpdatePackageStager.installVerified(release, target, { ByteArrayInputStream(bytes) }) { throw IOException("no installer") })
        assertFalse(target.exists())
    }
}
