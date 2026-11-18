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

/** Single-sheet XLSX tables. Formulas and formatted numbers are not guessed. */
object ExcelScheduleImporter {
    private const val maxBytes = 8 * 1024 * 1024
    fun parse(input: InputStream): DraftImport = parse(readLimited(input, maxBytes))

    fun parse(data: ByteArray): DraftImport {
        require(data.size <= maxBytes) { "Excel 文件过大" }
        val parts = mutableMapOf<String, ByteArray>()
        var expanded = 0
        var count = 0
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++count <= 256) { "Excel 文件内容过多" }
                val bytes = readLimited(zip, minOf(maxBytes - expanded, 2 * 1024 * 1024))
                expanded += bytes.size
                if (entry.name == "xl/sharedStrings.xml" || entry.name == "xl/styles.xml" ||
                    entry.name.matches(Regex("xl/worksheets/[^/]+\\.xml"))) {
                    require(parts.put(entry.name, bytes) == null) { "Excel 文件包含重复内容" }
                }
            }
        }
        val sheets = parts.filterKeys { it.startsWith("xl/worksheets/") }
        require(sheets.size == 1) { "请将课表另存为仅含一个工作表的 .xlsx" }
        val shared = mutableListOf<String>()
        parts["xl/sharedStrings.xml"]?.let { xml ->
            var inText = false
            var value = StringBuilder()
            scan(xml, start = { name, _ ->
                if (name == "si") value = StringBuilder()
                if (name == "t") inText = true
            }, text = { if (inText) value.append(it) }, end = { name ->
                if (name == "t") inText = false
                if (name == "si") shared += value.toString()
            })
        }
        val formats = mutableListOf<Int>()
        parts["xl/styles.xml"]?.let { xml ->
            var inCellFormats = false
            scan(xml, start = { name, attrs ->
                if (name == "cellXfs") inCellFormats = true
                if (name == "xf" && inCellFormats) formats += attrs.getValue("numFmtId")?.toIntOrNull() ?: 0
            }, end = { if (it == "cellXfs") inCellFormats = false })
        }
        val rows = mutableListOf<String>()
        var cells = sortedMapOf<Int, String>()
        var type = ""
        var style = 0
        var column = 0
        var value = StringBuilder()
        var capturing = false
        scan(sheets.values.single(), start = { name, attrs ->
            when (name) {
                "row" -> { require(rows.size < 2000) { "工作表超过 2000 行" }; cells = sortedMapOf() }
                "c" -> {
                    val reference = requireNotNull(attrs.getValue("r")) { "单元格缺少位置" }
                    require(reference.matches(Regex("[A-Z]{1,2}[1-9][0-9]*"))) { "不支持的单元格位置" }
                    column = reference.takeWhile { it in 'A'..'Z' }.fold(0) { acc, ch -> acc * 26 + (ch - 'A' + 1) }
                    require(column <= 64 && column !in cells) { "工作表列数过多或位置重复" }
                    type = attrs.getValue("t") ?: "n"
                    style = attrs.getValue("s")?.toIntOrNull() ?: 0
                    value = StringBuilder()
                }
                "v", "t" -> capturing = true
                "f" -> throw IllegalArgumentException("请先将公式粘贴为值")
                "mergeCell" -> throw IllegalArgumentException("请先取消合并单元格")
            }
        }, text = { if (capturing) value.append(it) }, end = { name ->
            when (name) {
                "v", "t" -> capturing = false
                "c" -> {
                    val raw = value.toString()
                    cells[column] = when {
                        raw.isEmpty() -> ""
                        type == "s" -> shared.getOrNull(raw.toIntOrNull() ?: -1)
                            ?: throw IllegalArgumentException("无效的共享文字索引")
                        type == "inlineStr" || type == "str" -> raw
                        type == "n" -> {
                            val format = if (formats.isEmpty() && style == 0) 0 else formats.getOrNull(style)
                            require(format == 0 || format == 1) { "请将日期、时间和自定义数字格式改为文本" }
                            require(raw.matches(Regex("[0-9]{1,7}(\\.0+)?"))) { "仅支持文本或整数；时间请存为文本" }
                            raw.substringBefore('.')
                        }
                        else -> throw IllegalArgumentException("请将单元格改为文本或整数")
                    }
                }
                "row" -> if (cells.isNotEmpty()) rows += (1..cells.lastKey()).joinToString(",") {
                    "\"" + cells[it].orEmpty().replace("\"", "\"\"") + "\""
                }
            }
        })
        return ScheduleTextImporter.parseMail(rows.joinToString("\n"))
    }

    private fun readLimited(input: InputStream, limit: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val size = input.read(buffer, 0, minOf(buffer.size, limit - output.size() + 1))
            if (size < 0) break
            require(output.size() + size <= limit) { "Excel 文件或解压内容过大" }
            output.write(buffer, 0, size)
        }
        return output.toByteArray()
    }

    private fun scan(xml: ByteArray, start: (String, Attributes) -> Unit = { _, _ -> },
                     text: (String) -> Unit = {}, end: (String) -> Unit = {}) {
        val handler = object : DefaultHandler2() {
            var depth = 0
            var chars = 0
            fun spreadsheet(uri: String) = uri == "http://schemas.openxmlformats.org/spreadsheetml/2006/main" ||
                uri == "http://purl.oclc.org/ooxml/spreadsheetml/main"
            override fun startDTD(name: String?, publicId: String?, systemId: String?) { throw SAXException("不支持文档类型声明") }
            override fun resolveEntity(publicId: String?, systemId: String?): InputSource { throw SAXException("不支持外部资源") }
            override fun fatalError(exception: SAXParseException) { throw exception }
            override fun startElement(uri: String, local: String, qName: String, attrs: Attributes) {
                require(++depth <= 64) { "Excel 内容嵌套过深" }
                if (spreadsheet(uri)) start(local, attrs)
            }
            override fun characters(ch: CharArray, offset: Int, length: Int) {
                chars += length
                require(chars <= 200_000) { "Excel 文字过长" }
                text(String(ch, offset, length))
            }
            override fun endElement(uri: String, local: String, qName: String) {
                depth--
                if (spreadsheet(uri)) end(local)
            }
        }
        val reader = SAXParserFactory.newInstance().apply { isNamespaceAware = true }.newSAXParser().xmlReader
        reader.setFeature("http://xml.org/sax/features/external-general-entities", false)
        reader.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        reader.setProperty("http://xml.org/sax/properties/lexical-handler", handler)
        reader.contentHandler = handler
        reader.entityResolver = handler
        reader.errorHandler = handler
        reader.parse(InputSource(ByteArrayInputStream(xml)))
    }
}
