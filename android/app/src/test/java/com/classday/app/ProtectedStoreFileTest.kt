package com.classday.app

import com.classday.app.core.DemoData
import com.classday.app.core.ProtectedStoreFile
import com.classday.app.core.StoreCodec
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class ProtectedStoreFileTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test
    fun invalidCandidateCannotReplaceValidPersonalData() {
        val file = File(temporary.root, "store.json")
        val store = ProtectedStoreFile(file)
        val original = DemoData.makeDocument()
        store.save(original)
        val bytes = file.readBytes()
        val course = original.courses.first()
        val invalid = original.copy(courses = listOf(course.copy(meetings = listOf(course.meetings.first().copy(startPeriod = 11, endPeriod = 12)))))
        assertThrows(IllegalStateException::class.java) { store.save(invalid) }
        assertArrayEquals(bytes, file.readBytes())
        assertEquals(original, store.load().document)
        assertFalse(File(temporary.root, "backups").exists())
    }

    @Test
    fun unreadableFileIsPreservedAndCannotBeOverwrittenByFallback() {
        val file = File(temporary.root, "store.json")
        val bytes = "{broken personal data".toByteArray()
        file.writeBytes(bytes)
        val store = ProtectedStoreFile(file)
        val result = store.load()
        assertNotNull(result.error)
        assertArrayEquals(bytes, file.readBytes())
        val recovery = File(temporary.root, "recovery").listFiles()!!.single()
        assertArrayEquals(bytes, recovery.readBytes())
        assertThrows(IllegalStateException::class.java) { store.save(result.document) }
        assertNotNull(store.load().error)
        assertEquals(1, File(temporary.root, "recovery").listFiles()!!.size)
        assertArrayEquals(bytes, file.readBytes())
    }

    @Test
    fun decodedButInvalidFileAlsoStaysProtected() {
        val file = File(temporary.root, "store.json")
        val original = DemoData.makeDocument()
        file.writeText(StoreCodec.exporting(original.copy(semester = original.semester.copy(periods = original.semester.periods.take(1)))))
        val bytes = file.readBytes()
        val result = ProtectedStoreFile(file).load()
        assertNotNull(result.error)
        assertThrows(IllegalStateException::class.java) { ProtectedStoreFile(file).save(original) }
        assertArrayEquals(bytes, file.readBytes())
    }

    @Test
    fun validSaveBacksUpOldDataAndReloadsNewData() {
        val file = File(temporary.root, "store.json")
        val store = ProtectedStoreFile(file)
        val original = store.load().document
        val updated = original.copy(semester = original.semester.copy(name = "新学期"))
        store.save(updated)
        assertNull(store.load().error)
        assertEquals(updated, store.load().document)
        val backup = File(temporary.root, "backups").listFiles()!!.single()
        assertEquals(original, StoreCodec.importing(backup.readText()).document)
    }

    @Test
    fun repeatedSavesPruneOldestBackupsBeyondLimit() {
        val file = File(temporary.root, "store.json")
        val store = ProtectedStoreFile(file)
        val limit = ProtectedStoreFile.DEFAULT_MAX_BACKUPS
        val base = DemoData.makeDocument()
        store.save(base.copy(semester = base.semester.copy(name = "学期-0")))
        for (index in 1..(limit + 2)) {
            store.save(base.copy(semester = base.semester.copy(name = "学期-$index")))
        }
        val backups = File(temporary.root, "backups").listFiles()!!.filter { it.isFile }
        assertEquals(limit, backups.size)
        val retainedNames = backups
            .mapNotNull { StoreCodec.importing(it.readText()).document?.semester?.name }
            .toSet()
        assertEquals((2..(limit + 1)).map { "学期-$it" }.toSet(), retainedNames)
        assertEquals("学期-${limit + 2}", store.load().document.semester.name)
    }

    @Test
    fun distinctInvalidFilesPruneOldestRecoveryCopiesWhileKeepingCurrentAndDeduplicating() {
        val file = File(temporary.root, "store.json")
        val store = ProtectedStoreFile(file)
        val limit = ProtectedStoreFile.DEFAULT_MAX_RECOVERY_FILES
        for (index in 1..limit) {
            file.writeText("{corrupt-$index")
            assertNotNull(store.load().error)
        }
        // Encountering corrupt-1 again refreshes its recency without creating a duplicate file.
        file.writeText("{corrupt-1")
        assertNotNull(store.load().error)
        assertEquals(limit, File(temporary.root, "recovery").listFiles()!!.filter { it.isFile }.size)

        for (index in (limit + 1)..(limit + 2)) {
            file.writeText("{corrupt-$index")
            assertNotNull(store.load().error)
        }
        // Re-loading the latest invalid file must deduplicate without evicting another copy.
        assertNotNull(store.load().error)
        val recoveries = File(temporary.root, "recovery").listFiles()!!.filter { it.isFile }
        assertEquals(limit, recoveries.size)
        val retainedContents = recoveries.map { it.readText() }.toSet()
        val expected = (listOf(1) + (4..(limit + 2))).map { "{corrupt-$it" }.toSet()
        assertEquals(expected, retainedContents)
    }
}
