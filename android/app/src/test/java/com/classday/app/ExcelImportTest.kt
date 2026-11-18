package com.classday.app

import com.classday.app.core.ExcelScheduleImporter
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Test

class ExcelImportTest {
    private val ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private fun sheet(rows: String, extras: String = "") = "<worksheet xmlns=\"$ns\"><sheetData>$rows</sheetData>$extras</worksheet>"
    private fun cell(ref: String, text: String) = "<c r=\"$ref\" t=\"inlineStr\"><is><t>$text</t></is></c>"
    private fun header() = "<row r=\"1\">${cell("A1", "课程名称")}${cell("B1", "星期")}${cell("C1", "节次")}${cell("D1", "教室")}${cell("E1", "周次")}</row>"
    private fun archive(vararg parts: Pair<String, String>): ByteArray {
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { zip -> parts.forEach { (name, text) ->
            zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry()
        } }
        return bytes.toByteArray()
    }
    private fun parse(rows: String, extras: String = "") = ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to sheet(rows, extras)))

    @Test fun inlineStringsSparseCellsAndIntegerPeriods() {
        val row = "<row r=\"2\">${cell("A2", "数学,基础 &amp; 应用")}${cell("B2", "周一")}<c r=\"C2\"><v>3.0</v></c>${cell("E2", "2-8")}</row>"
        val draft = parse(header() + row).drafts.single()
        assertEquals("数学,基础 & 应用", draft.name)
        assertEquals("", draft.location)
        assertEquals((2..8).toList(), draft.weeks)
        assertEquals(3, draft.meetings.single().startPeriod)
    }

    @Test fun sharedRichStringsAndNormalStyles() {
        val shared = "<sst xmlns=\"$ns\"><si><r><t>高等</t></r><r><t>数学</t></r></si></sst>"
        val styles = "<styleSheet xmlns=\"$ns\"><cellXfs><xf numFmtId=\"0\"/><xf numFmtId=\"0\"/></cellXfs></styleSheet>"
        val row = "<row><c r=\"A2\" t=\"s\"><v>0</v></c>${cell("B2", "周二")}<c r=\"C2\" s=\"1\"><v>2</v></c></row>"
        val draft = ExcelScheduleImporter.parse(archive("xl/worksheets/lesson.xml" to sheet(header() + row),
            "xl/sharedStrings.xml" to shared, "xl/styles.xml" to styles)).drafts.single()
        assertEquals("高等数学", draft.name)
        assertEquals(2, draft.meetings.single().weekday)
    }

    @Test fun refusesMultipleSheetsFormulasAndMergedCells() {
        assertThrows(IllegalArgumentException::class.java) {
            ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to sheet(header()), "xl/worksheets/sheet2.xml" to sheet(header())))
        }
        assertThrows(IllegalArgumentException::class.java) { parse(header() + "<row><c r=\"A2\"><f>1+1</f><v>2</v></c></row>") }
        assertThrows(IllegalArgumentException::class.java) { parse(header(), "<mergeCells><mergeCell ref=\"A1:B1\"/></mergeCells>") }
    }

    @Test fun refusesNumericTimesAndDateFormatsInsteadOfGuessing() {
        assertThrows(IllegalArgumentException::class.java) { parse(header() + "<row><c r=\"A2\"><v>0.333333</v></c></row>") }
        val styles = "<styleSheet xmlns=\"$ns\"><cellXfs><xf numFmtId=\"14\"/></cellXfs></styleSheet>"
        assertThrows(IllegalArgumentException::class.java) {
            ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to sheet(header() + "<row><c r=\"A2\"><v>45000</v></c></row>"), "xl/styles.xml" to styles))
        }
    }

    @Test fun refusesBrokenIndexesColumnsAndXml() {
        assertThrows(IllegalArgumentException::class.java) { parse("<row><c r=\"A1\" t=\"s\"><v>5</v></c></row>") }
        assertThrows(IllegalArgumentException::class.java) { parse("<row>${cell("ZZ1", "far away")}</row>") }
        assertThrows(Exception::class.java) { ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to "<broken>")) }
        assertThrows(IllegalArgumentException::class.java) { ExcelScheduleImporter.parse("not xlsx".toByteArray()) }
    }

    @Test fun refusesDtdAndExcessiveExpansion() {
        val dtd = "<!DOCTYPE worksheet [<!ENTITY x SYSTEM 'file:///never-read'>]><worksheet xmlns=\"$ns\">&x;</worksheet>"
        assertThrows(Exception::class.java) { ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to dtd)) }
        assertThrows(IllegalArgumentException::class.java) { ExcelScheduleImporter.parse(archive("xl/worksheets/sheet1.xml" to "x".repeat(2 * 1024 * 1024 + 1))) }
        assertThrows(IllegalArgumentException::class.java) { ExcelScheduleImporter.parse(ByteArray(8 * 1024 * 1024 + 1)) }
    }
}
