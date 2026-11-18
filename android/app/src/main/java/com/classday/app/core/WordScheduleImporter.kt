package com.classday.app.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.ZipInputStream
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.SAXParseException
import org.xml.sax.ext.DefaultHandler2

/** Text/table-only DOCX import; no macros, embedded files, links or remote resources. */
object WordScheduleImporter {
    private const val maxBytes = 8 * 1024 * 1024
    private const val maxXmlBytes = 2 * 1024 * 1024

    fun parse(input: InputStream): DraftImport = parse(readLimited(input, maxBytes))

    fun parse(data: ByteArray): DraftImport {
        require(data.size <= maxBytes) { "Word 文件超过 8 MB，请精简后重试" }
        var xml: ByteArray? = null
        var expanded = 0
        var entries = 0
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++entries <= 256) { "Word 文件内容过多，请精简后重试" }
                val bytes = readLimited(zip, minOf(maxBytes - expanded, if (entry.name == "word/document.xml") maxXmlBytes else maxBytes))
                expanded += bytes.size
                if (entry.name == "word/document.xml") {
                    require(xml == null) { "Word 文件正文重复，无法导入" }
                    xml = bytes
                }
            }
        }
        val document = requireNotNull(xml) { "不是可读取的 .docx 文件，请使用 Word 另存为 .docx" }
        val handler = WordTextHandler()
        val reader = SAXParserFactory.newInstance().apply { isNamespaceAware = true }.newSAXParser().xmlReader
        // Refuse DTDs via the lexical callback before any entity can be expanded.
        reader.setFeature("http://xml.org/sax/features/external-general-entities", false)
        reader.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        reader.setProperty("http://xml.org/sax/properties/lexical-handler", handler)
        reader.contentHandler = handler
        reader.entityResolver = handler
        reader.errorHandler = handler
        reader.parse(InputSource(ByteArrayInputStream(document)))
        return ScheduleTextImporter.parseMail(handler.text())
    }

    private fun readLimited(input: InputStream, limit: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer, 0, minOf(buffer.size, limit - output.size() + 1))
            if (count < 0) break
            require(output.size() + count <= limit) { "Word 文件或解压内容过大，请精简后重试" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private class WordTextHandler : DefaultHandler2() {
        private val lines = mutableListOf<String>()
        private val paragraph = StringBuilder()
        private var cells: MutableList<String>? = null
        private var cell: StringBuilder? = null
        private var inText = false
        private var characterCount = 0
        private var depth = 0

        private fun isWord(uri: String) = uri == "http://schemas.openxmlformats.org/wordprocessingml/2006/main" ||
            uri == "http://purl.oclc.org/ooxml/wordprocessingml/main"

        override fun startDTD(name: String?, publicId: String?, systemId: String?) {
            throw SAXException("不支持带文档类型声明的 Word 文件")
        }

        override fun resolveEntity(publicId: String?, systemId: String?): InputSource {
            throw SAXException("不支持外部资源")
        }

        override fun fatalError(exception: SAXParseException) { throw exception }

        override fun startElement(uri: String, localName: String, qName: String, attributes: Attributes) {
            require(++depth <= 64) { "Word 文件嵌套过深" }
            if (!isWord(uri)) return
            when (localName) {
                "vMerge", "hMerge" -> throw SAXException("请先取消表格合并单元格")
                "gridSpan" -> require((0 until attributes.length).none {
                    attributes.getLocalName(it) == "val" && attributes.getValue(it) != "1"
                }) { "请先取消表格合并单元格" }
                "tr" -> { require(cells == null) { "暂不支持嵌套表格" }; cells = mutableListOf() }
                "tc" -> cell = StringBuilder()
                "t" -> inText = true
                "tab", "br" -> (cell ?: paragraph).append(' ')
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) {
            characterCount += length
            require(characterCount <= 200_000) { "Word 正文过长，请精简后重试" }
            if (inText) (cell ?: paragraph).append(ch, start, length)
        }

        override fun endElement(uri: String, localName: String, qName: String) {
            depth--
            if (!isWord(uri)) return
            when (localName) {
                "t" -> inText = false
                "p" -> if (cell != null) cell!!.append(' ') else {
                    if (paragraph.isNotBlank()) lines += paragraph.toString().trim()
                    paragraph.clear()
                }
                "tc" -> { cells?.add(cell.toString().trim()); cell = null }
                "tr" -> {
                    lines += cells.orEmpty().joinToString(",") { "\"" + it.replace("\"", "\"\"") + "\"" }
                    cells = null
                }
            }
        }

        fun text(): String = lines.joinToString("\n")
    }
}
