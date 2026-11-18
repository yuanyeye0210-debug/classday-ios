package com.classday.app.core

import kotlin.math.min
import kotlin.math.sqrt

data class PdfRenderSize(val width: Int, val height: Int)

/** Bound PDF OCR work before allocating bitmaps. No partially read document is imported. */
object PdfImportPolicy {
    const val maxBytes = 8L * 1024 * 1024
    const val maxPages = 10
    const val maxCharacters = 100_000
    const val maxPixels = 2_000_000

    fun acceptsFile(size: Long) = size in 1..maxBytes
    fun acceptsPages(count: Int) = count in 1..maxPages

    fun renderSize(width: Int, height: Int): PdfRenderSize? {
        if (width < 1 || height < 1) return null
        val scale = min(2.0, min(1800.0 / maxOf(width, height), sqrt(maxPixels.toDouble() / width / height)))
        val renderedWidth = (width * scale).toInt().coerceAtLeast(1)
        val renderedHeight = (height * scale).toInt().coerceAtLeast(1)
        if (renderedWidth.toLong() * renderedHeight > maxPixels) return null
        return PdfRenderSize(renderedWidth, renderedHeight)
    }

    fun combinePages(pages: List<String>): String {
        require(acceptsPages(pages.size)) { "PDF 页数超出范围" }
        require(pages.sumOf { it.length.toLong() } + pages.size - 1 <= maxCharacters) { "PDF 文字过长" }
        return pages.joinToString("\n")
    }

    fun draftsFromPages(pages: List<String>): DraftImport {
        val parsed = ScheduleTextImporter.parseMail(combinePages(pages))
        val blankPages = pages.mapIndexedNotNull { index, text ->
            if (text.isBlank()) "第 ${index + 1} 页没有识别到文字，请核对原文件" else null
        }
        return parsed.copy(unparsed = parsed.unparsed + blankPages)
    }
}
