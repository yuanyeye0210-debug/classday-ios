package com.classday.app

import com.classday.app.core.PdfImportPolicy
import com.classday.app.core.PdfRenderSize
import com.classday.app.core.ScheduleTextImporter
import org.junit.Assert.*
import org.junit.Test

class PdfImportPolicyTest {
    @Test fun fileAndPageLimitsIncludeBoundaries() {
        assertFalse(PdfImportPolicy.acceptsFile(-1))
        assertFalse(PdfImportPolicy.acceptsFile(0))
        assertTrue(PdfImportPolicy.acceptsFile(PdfImportPolicy.maxBytes))
        assertFalse(PdfImportPolicy.acceptsFile(PdfImportPolicy.maxBytes + 1))
        assertFalse(PdfImportPolicy.acceptsPages(0))
        assertTrue(PdfImportPolicy.acceptsPages(10))
        assertFalse(PdfImportPolicy.acceptsPages(11))
    }

    @Test fun rendersWithinMemoryAndDimensionLimits() {
        for ((width, height) in listOf(595 to 842, 842 to 595, 10000 to 10000, Int.MAX_VALUE to 1, 1 to Int.MAX_VALUE)) {
            val size = PdfImportPolicy.renderSize(width, height)!!
            assertTrue(size.width >= 1 && size.height >= 1)
            assertTrue(size.width <= 1800 && size.height <= 1800)
            assertTrue(size.width.toLong() * size.height <= PdfImportPolicy.maxPixels)
        }
        assertNull(PdfImportPolicy.renderSize(0, 842))
        assertNull(PdfImportPolicy.renderSize(595, -1))
    }

    @Test fun combinesInPageOrderAndPreservesSafeParsing() {
        val text = PdfImportPolicy.combinePages(listOf("高数 周一 08:00-09:40", "英语 周二 10:00-11:40", "物理 周三 08:00-09:40 停课"))
        val parsed = ScheduleTextImporter.parseMail(text)
        assertEquals(listOf("高数", "英语"), parsed.drafts.map { it.name })
        assertEquals(1, parsed.unparsed.size)
        assertEquals("\n", PdfImportPolicy.combinePages(listOf("", "")))
        val mixed = PdfImportPolicy.draftsFromPages(listOf("高数 周一 08:00-09:40", ""))
        assertEquals(1, mixed.drafts.size)
        assertTrue(mixed.unparsed.single().contains("第 2 页"))
    }

    @Test fun rejectsOversizedTextAndPartialPageLists() {
        assertThrows(IllegalArgumentException::class.java) { PdfImportPolicy.combinePages(emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { PdfImportPolicy.combinePages(List(11) { "" }) }
        assertThrows(IllegalArgumentException::class.java) { PdfImportPolicy.combinePages(listOf("x".repeat(100_001))) }
    }

    @Test fun doesNotUpscaleSmallPagesBeyondDouble() {
        assertEquals(PdfRenderSize(200, 100), PdfImportPolicy.renderSize(100, 50))
        assertEquals(PdfRenderSize(2, 2), PdfImportPolicy.renderSize(1, 1))
        assertEquals(PdfRenderSize(4, 2), PdfImportPolicy.renderSize(2, 1))
    }

    @Test fun downscalesOversizedPagesWithoutDroppingReadableSize() {
        // 横向超长页先受 1800 长边限制，不被压成不可识别的小图。
        assertEquals(PdfRenderSize(1800, 450), PdfImportPolicy.renderSize(4000, 1000))
        // 方形大页同时受长边和 200 万像素限制。
        assertEquals(PdfRenderSize(1414, 1414), PdfImportPolicy.renderSize(2000, 2000))
        val a4 = PdfImportPolicy.renderSize(595, 842)!!
        assertTrue(a4.width >= 1180 && a4.height >= 1670)
    }

    @Test fun characterLimitCountsPageSeparators() {
        assertEquals(100_000, PdfImportPolicy.combinePages(listOf("x".repeat(99_998), "y")).length)
        assertThrows(IllegalArgumentException::class.java) {
            PdfImportPolicy.combinePages(listOf("x".repeat(99_999), "y"))
        }
        val exactTenPages = List(10) { index -> if (index == 0) "x".repeat(99_982) else "x" }
        assertEquals(100_000, PdfImportPolicy.combinePages(exactTenPages).length)
        assertThrows(IllegalArgumentException::class.java) {
            PdfImportPolicy.combinePages(listOf("x".repeat(99_983)) + List(9) { "x" })
        }
    }

    @Test fun reportsEveryBlankPageInPageOrder() {
        val parsed = PdfImportPolicy.draftsFromPages(listOf("", "高数 周一 08:00-09:40", "   "))
        assertEquals(listOf("高数"), parsed.drafts.map { it.name })
        assertEquals(2, parsed.unparsed.size)
        assertTrue(parsed.unparsed[0].startsWith("第 1 页"))
        assertTrue(parsed.unparsed[1].startsWith("第 3 页"))
    }
}
