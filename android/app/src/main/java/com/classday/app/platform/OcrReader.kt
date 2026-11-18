package com.classday.app.platform

import android.content.Context
import android.net.Uri
import android.graphics.Bitmap
import com.classday.app.core.OcrLine
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object OcrReader {
    suspend fun read(context: Context, uri: Uri): String = withContext(Dispatchers.IO) {
        val image = InputImage.fromFilePath(context, uri)
        recognize(image).text
    }

    suspend fun readBitmap(bitmap: Bitmap): String = withContext(Dispatchers.IO) {
        recognize(InputImage.fromBitmap(bitmap, 0)).text
    }

    /** 带坐标的逐行结果，供网格课表按列还原。 */
    suspend fun readBitmapLines(bitmap: Bitmap): List<OcrLine> = withContext(Dispatchers.IO) {
        val text = recognize(InputImage.fromBitmap(bitmap, 0))
        text.textBlocks.flatMap { block ->
            block.lines.mapNotNull { line ->
                val box = line.boundingBox ?: return@mapNotNull null
                val content = line.text.trim()
                if (content.isEmpty()) null
                else OcrLine(
                    text = content,
                    cx = box.exactCenterX(),
                    cy = box.exactCenterY(),
                )
            }
        }
    }

    private fun recognize(image: InputImage): com.google.mlkit.vision.text.Text {
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        try {
            return Tasks.await(recognizer.process(image))
        } finally {
            recognizer.close()
        }
    }
}