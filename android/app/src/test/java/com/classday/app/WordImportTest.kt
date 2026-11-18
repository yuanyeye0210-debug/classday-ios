package com.classday.app

import com.classday.app.core.WordScheduleImporter
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Test

class WordImportTest {
    private fun docx(body: String): ByteArray = zip("word/document.xml",
        "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>$body</w:body></w:document>")

    private fun zip(name: String, text: String): ByteArray {
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { zip ->
            zip.putNextEntry(ZipEntry(name))
            zip.write(text.toByteArray(Charsets.UTF_8))
            zip.closeEntry()
        }
        return bytes.toByteArray()
    }

    private fun paragraph(text: String) = "<w:p><w:r><w:t>$text</w:t></w:r></w:p>"
    private fun row(vararg cells: String) = "<w:tr>" + cells.joinToString("") { "<w:tc>${paragraph(it)}</w:tc>" } + "</w:tr>"

    @Test fun tablePreservesCellsEntitiesWeeksAndSplitRuns() {
        val bytes = docx(paragraph("本学期课表") + "<w:tbl>" +
            row("课程名称", "星期", "节次", "周次", "教室") +
            row("数学,基础 &amp; 应用", "周一", "1-2", "2-8", "A301") + "</w:tbl>")
        val result = WordScheduleImporter.parse(bytes.inputStream())
        assertEquals("数学,基础 & 应用", result.drafts.single().name)
        assertEquals((2..8).toList(), result.drafts.single().weeks)
        assertEquals("A301", result.drafts.single().location)
        val split = docx("<w:p><w:r><w:t>高等</w:t></w:r><w:r><w:t>数学 周一 08:00-09:40</w:t></w:r></w:p>")
        assertEquals("高等数学", WordScheduleImporter.parse(split).drafts.single().name)
    }

    @Test fun proseAndCancellationUseExistingSafeMailPolicy() {
        val result = WordScheduleImporter.parse(docx(paragraph("英语 周二 10:00-11:40") + paragraph("物理 周三 08:00-09:40 停课")))
        assertEquals(listOf("英语"), result.drafts.map { it.name })
        assertEquals(1, result.unparsed.size)
        assertTrue(WordScheduleImporter.parse(docx(paragraph("没有课表"))).drafts.isEmpty())
    }

    @Test fun rejectsWrongOrMalformedDocuments() {
        assertThrows(IllegalArgumentException::class.java) { WordScheduleImporter.parse("not a zip".toByteArray()) }
        assertThrows(IllegalArgumentException::class.java) { WordScheduleImporter.parse(zip("other.xml", "<x/>")) }
        assertThrows(Exception::class.java) { WordScheduleImporter.parse(zip("word/document.xml", "<broken>")) }
    }

    @Test fun rejectsDtdBeforeEntityExpansion() {
        val external = "<!DOCTYPE document [<!ENTITY xxe SYSTEM 'file:///should-never-be-read'>]><document>&xxe;</document>"
        assertThrows(Exception::class.java) { WordScheduleImporter.parse(zip("word/document.xml", external)) }
        val internal = "<!DOCTYPE document [<!ENTITY x 'expanded'>]><document>&x;</document>"
        assertThrows(Exception::class.java) { WordScheduleImporter.parse(zip("word/document.xml", internal)) }
    }

    @Test fun rejectsOversizedXmlAndCompressedInput() {
        assertThrows(IllegalArgumentException::class.java) { WordScheduleImporter.parse(ByteArray(8 * 1024 * 1024 + 1)) }
        assertThrows(IllegalArgumentException::class.java) { WordScheduleImporter.parse(zip("word/document.xml", "x".repeat(2 * 1024 * 1024 + 1))) }
    }

    @Test fun rejectsExpandedArchiveAndTooManyEntries() {
        assertThrows(IllegalArgumentException::class.java) {
            WordScheduleImporter.parse(zip("media/large", "x".repeat(8 * 1024 * 1024 + 1)))
        }
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { zip ->
            repeat(257) { zip.putNextEntry(ZipEntry("part$it")); zip.closeEntry() }
        }
        assertThrows(IllegalArgumentException::class.java) { WordScheduleImporter.parse(bytes.toByteArray()) }
    }

    @Test fun rejectsMergedAndNestedTablesInsteadOfGuessing() {
        assertThrows(Exception::class.java) {
            WordScheduleImporter.parse(docx("<w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>${paragraph("周一")}</w:tc></w:tr></w:tbl>"))
        }
        assertThrows(Exception::class.java) {
            WordScheduleImporter.parse(docx("<w:tbl><w:tr><w:tc><w:tbl>${row("nested")}</w:tbl></w:tc></w:tr></w:tbl>"))
        }
    }
}
