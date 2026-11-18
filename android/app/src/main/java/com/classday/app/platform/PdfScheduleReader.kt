package com.classday.app.platform

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import com.classday.app.core.DraftImport
import com.classday.app.core.OcrGridParser
import com.classday.app.core.OcrLine
import com.classday.app.core.PdfImportPolicy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

object PdfScheduleReader {
    suspend fun read(context: Context, uri: Uri): DraftImport = withContext(Dispatchers.IO) {
        val descriptor = context.contentResolver.openFileDescriptor(uri, "r") ?: error("无法打开 PDF")
        descriptor.use { file ->
            require(PdfImportPolicy.acceptsFile(file.statSize)) { "PDF 大小未知或超过 8 MB" }
            PdfRenderer(file).use { renderer ->
                require(PdfImportPolicy.acceptsPages(renderer.pageCount)) { "PDF 需为 1–10 页" }
                val texts = mutableListOf<String>()
                val gridLines = mutableListOf<OcrLine>()
                var characters = 0L
                repeat(renderer.pageCount) { index ->
                    coroutineContext.ensureActive()
                    renderer.openPage(index).use { page ->
                        val size = requireNotNull(PdfImportPolicy.renderSize(page.width, page.height))
                        val bitmap = Bitmap.createBitmap(size.width, size.height, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val lines = OcrReader.readBitmapLines(bitmap)
                            gridLines += lines
                            val text = OcrReader.readBitmap(bitmap)
                            characters += text.length
                            require(characters <= PdfImportPolicy.maxCharacters) { "PDF 文字过长" }
                            texts += text
                        } finally {
                            bitmap.recycle()
                        }
                    }
                }
                coroutineContext.ensureActive()
                // 网格课表优先按坐标还原（星期几来自列位置）；还原不出再回落纯文本解析。
                OcrGridParser.parse(gridLines) ?: PdfImportPolicy.draftsFromPages(texts)
            }
        }
    }
}
