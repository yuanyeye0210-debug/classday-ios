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
}
