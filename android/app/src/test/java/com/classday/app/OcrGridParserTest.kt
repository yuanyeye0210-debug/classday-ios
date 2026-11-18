package com.classday.app

import com.classday.app.core.OcrGridParser
import com.classday.app.core.OcrLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 真实样本：教务系统导出的网格课表 PDF（节次为行、星期为列），
 * 每个格子形如「课程名(课程号) / (1-2节)9-16周/校区:xx/地点:C220/教师:张江/学分:3.0」。
 */
class OcrGridParserTest {
    private fun header(cy: Float = 100f): List<OcrLine> = listOf(
        OcrLine("时间", 60f, cy),
        OcrLine("节次", 60f, cy + 30f),
        OcrLine("星期一", 200f, cy),
        OcrLine("星期二", 320f, cy),
        OcrLine("星期三", 440f, cy),
        OcrLine("星期四", 560f, cy),
        OcrLine("星期五", 680f, cy),
        OcrLine("星期六", 800f, cy),
        OcrLine("星期日", 920f, cy),
    )

    private fun cell(cx: Float, cy: Float, name: String, detail: String) = listOf(
        OcrLine(name, cx, cy),
        OcrLine(detail, cx, cy + 22f),
    )

    @Test fun realTimetableGridBecomesCoursesWithCorrectWeekdayAndPeriods() {
        val lines = header() +
            cell(200f, 200f, "高等数学C(2)(01805191)", "(1-2节)9-16周/校区:紫金山/地点:C220/教师:张江/学分:3.0") +
            cell(320f, 200f, "现代制造技术基础(09A35029)", "(1-2节)1-16周/校区:紫金山/地点:D209/教师:张建/学分:4.0") +
            cell(200f, 300f, "信号与系统(16583109)", "(3-4节)3周,7周,11周,15周/校区:紫金山/地点:FJ106/教师:李四/学分:0.0")

        val result = assertNotNull(OcrGridParser.parse(lines)).let { OcrGridParser.parse(lines)!! }
        val math = result.drafts.first { it.name.contains("高等数学") }
        assertEquals(1, math.meetings.single().weekday)
        assertEquals(1, math.meetings.single().startPeriod)
        assertEquals(2, math.meetings.single().endPeriod)
        assertEquals("C220", math.meetings.single().location)
        assertEquals((9..16).toList(), math.weeks)

        val signal = result.drafts.first { it.name.contains("信号与系统") }
        assertEquals(listOf(3, 7, 11, 15), signal.weeks)

        assertTrue(result.unparsed.isEmpty())
    }

    @Test fun sameCourseInTwoRoomsKeepsBothMeetings() {
        val lines = header() +
            cell(200f, 200f, "现代制造技术实验D(00883016)", "(1-1节)9-16周/校区:紫金山/地点:C417/教师:王五/学分:2.0") +
            cell(440f, 200f, "现代制造技术实验D(00883016)", "(1-1节)9-16周/校区:紫金山/地点:C419/教师:王五/学分:2.0")

        val result = OcrGridParser.parse(lines)!!
        val course = result.drafts.first { it.name.contains("现代制造技术实验") }
        assertEquals(2, course.meetings.size)
        assertEquals(setOf(1, 3), course.meetings.map { it.weekday }.toSet())
        assertEquals("C417 / C419", course.location)
    }

    @Test fun withoutWeekdayHeaderFallsBackToNull() {
        val lines = listOf(
            OcrLine("高等数学", 200f, 200f),
            OcrLine("(1-2节)1-16周", 200f, 220f),
        )
        assertNull(OcrGridParser.parse(lines))
    }
}