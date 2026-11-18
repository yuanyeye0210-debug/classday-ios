package com.classday.app

import com.classday.app.core.CameraCaptureFiles
import java.nio.file.Files
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class CameraCaptureFilesTest {
    @Test fun revisitAfterInterruptedOcrCleansOnlyExpiredInactiveCaptures() {
        val root = Files.createTempDirectory("classday-camera-restart-test").toFile()
        try {
            val now = 2_000_000_000_000L
            val cutoff = now - CameraCaptureFiles.retentionMillis
            val abandoned = CameraCaptureFiles.create(root).apply { writeText("interrupted OCR"); assertTrue(setLastModified(cutoff)) }
            val activeCamera = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(cutoff - 1)) }
            val activeOcr = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(cutoff - 1)) }
            val recent = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(cutoff + 1)) }
            val future = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(now + 1)) }
            val foreign = File(root, "notes.jpg").apply { writeText("keep"); assertTrue(setLastModified(cutoff - 1)) }
            val nested = File(root, "nested").apply { mkdirs() }
            val nestedPhoto = CameraCaptureFiles.create(nested).apply { assertTrue(setLastModified(cutoff - 1)) }
            assertEquals(1, CameraCaptureFiles.removeExpired(root, setOf(activeCamera.name, activeOcr.name), now))
            assertFalse(abandoned.exists())
            listOf(activeCamera, activeOcr, recent, future, foreign, nestedPhoto).forEach { assertTrue(it.exists()) }
            // A new process has no active OCR; the same expired file can now be removed.
            assertEquals(2, CameraCaptureFiles.removeExpired(root, emptySet(), now))
            assertEquals(0, CameraCaptureFiles.removeExpired(root, emptySet(), now))
            assertTrue(foreign.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun invalidClockAndMissingDirectoriesDoNotTriggerDeletion() {
        val root = Files.createTempDirectory("classday-camera-restart-test").toFile()
        try {
            val file = CameraCaptureFiles.create(root)
            assertEquals(0, CameraCaptureFiles.removeExpired(root, emptySet(), -1))
            assertTrue(file.exists())
            assertEquals(0, CameraCaptureFiles.removeExpired(File(root, "missing"), emptySet(), Long.MAX_VALUE))
        } finally { root.deleteRecursively() }
    }
    @Test fun sweepSkipsDirectoriesAndEntriesWithUnknownTime() {
        val root = Files.createTempDirectory("classday-camera-restart-test").toFile()
        try {
            val now = 2_000_000_000_000L
            val cutoff = now - CameraCaptureFiles.retentionMillis
            // A directory can accidentally carry a generated name; the sweep must only delete regular files.
            val disguisedDirectory = File(root, "capture-" + "a".repeat(36) + ".jpg")
                .apply { mkdirs(); assertTrue(setLastModified(cutoff - 1)) }
            // An unreadable clock (0) is not proof of age and must not trigger deletion.
            val unknownTime = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(0)) }
            val expired = CameraCaptureFiles.create(root).apply { assertTrue(setLastModified(cutoff - 1)) }

            assertEquals(1, CameraCaptureFiles.removeExpired(root, emptySet(), now))
            assertTrue(disguisedDirectory.isDirectory)
            assertTrue(unknownTime.exists())
            assertFalse(expired.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun capturesAreDistinctAndOnlyOwnedFilesAreRemoved() {
        val root = Files.createTempDirectory("classday-camera-test").toFile()
        try {
            val directory = File(root, "captures")
            val first = CameraCaptureFiles.create(directory)
            val second = CameraCaptureFiles.create(directory)
            assertNotEquals(first.name, second.name)
            assertEquals(first, CameraCaptureFiles.resolve(directory, first.name))
            assertFalse(CameraCaptureFiles.readablePhoto(first))
            first.writeBytes(byteArrayOf(1, 2, 3))
            assertTrue(CameraCaptureFiles.readablePhoto(first))
            assertTrue(CameraCaptureFiles.remove(directory, first.name))
            assertFalse(first.exists())
            assertTrue(second.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun traversalForeignNamesAndOversizedPhotosAreRejected() {
        val root = Files.createTempDirectory("classday-camera-test").toFile()
        try {
            val foreign = File(root, "notes.jpg").apply { writeText("keep") }
            assertNull(CameraCaptureFiles.resolve(root, "../notes.jpg"))
            assertNull(CameraCaptureFiles.resolve(root, foreign.name))
            assertFalse(CameraCaptureFiles.remove(root, foreign.name))
            assertEquals("keep", foreign.readText())
            assertNull(CameraCaptureFiles.resolve(root, null))
            val capture = CameraCaptureFiles.create(root)
            java.io.RandomAccessFile(capture, "rw").use { it.setLength(CameraCaptureFiles.maxBytes + 1) }
            assertFalse(CameraCaptureFiles.readablePhoto(capture))
        } finally { root.deleteRecursively() }
    }

    @Test fun createRejectsRegularFileAsDirectoryAndRemoveIsIdempotent() {
        val root = Files.createTempDirectory("classday-camera-test").toFile()
        try {
            val notADirectory = File(root, "captures").apply { writeText("keep") }
            assertThrows(IllegalArgumentException::class.java) { CameraCaptureFiles.create(notADirectory) }
            assertEquals("keep", notADirectory.readText())
            val directory = File(root, "nested/captures")
            val capture = CameraCaptureFiles.create(directory)
            assertTrue(directory.isDirectory)
            assertTrue(CameraCaptureFiles.remove(directory, capture.name))
            assertTrue(CameraCaptureFiles.remove(directory, capture.name))
            assertFalse(CameraCaptureFiles.remove(directory, null))
        } finally { root.deleteRecursively() }
    }

    @Test fun sizeBoundarySiblingDirectoriesAndInvalidNames() {
        val root = Files.createTempDirectory("classday-camera-test").toFile()
        try {
            val first = File(root, "first")
            val second = File(root, "second").apply { mkdirs() }
            val capture = CameraCaptureFiles.create(first)
            java.io.RandomAccessFile(capture, "rw").use { it.setLength(CameraCaptureFiles.maxBytes) }
            assertTrue(CameraCaptureFiles.readablePhoto(capture))
            java.io.RandomAccessFile(capture, "rw").use { it.setLength(CameraCaptureFiles.maxBytes + 1) }
            assertFalse(CameraCaptureFiles.readablePhoto(capture))
            assertFalse(CameraCaptureFiles.readablePhoto(second))

            val sibling = File(second, capture.name).apply { writeText("keep") }
            assertTrue(CameraCaptureFiles.remove(first, capture.name))
            assertFalse(capture.exists())
            assertEquals("keep", sibling.readText())

            val fakeUuid = "capture-" + "z".repeat(36) + ".jpg"
            assertNull(CameraCaptureFiles.resolve(second, fakeUuid))
            assertFalse(CameraCaptureFiles.remove(second, fakeUuid))
            val tooShort = "capture-" + "a".repeat(35) + ".jpg"
            assertNull(CameraCaptureFiles.resolve(second, tooShort))
        } finally { root.deleteRecursively() }
    }

    @Test fun symlinkedOwnedNameCannotEscapeCaptureDirectory() {
        val root = Files.createTempDirectory("classday-camera-test").toFile()
        try {
            val directory = File(root, "captures")
            CameraCaptureFiles.create(directory)
            val outside = File(root, "outside.jpg").apply { writeText("keep") }
            val link = File(directory, "capture-" + "a".repeat(36) + ".jpg")
            // Symlink creation needs privileges on some Windows hosts; exercise it where supported.
            try {
                Files.createSymbolicLink(link.toPath(), outside.toPath())
            } catch (_: UnsupportedOperationException) {
                return
            } catch (_: java.io.IOException) {
                return
            } catch (_: SecurityException) {
                return
            }
            assertNull(CameraCaptureFiles.resolve(directory, link.name))
            assertFalse(CameraCaptureFiles.remove(directory, link.name))
            assertEquals("keep", outside.readText())
        } finally { root.deleteRecursively() }
    }
}
