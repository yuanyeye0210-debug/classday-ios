package com.classday.app

import com.classday.app.core.Course
import com.classday.app.core.DemoData
import com.classday.app.core.Meeting
import com.classday.app.core.StoreCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 课程「班级」字段：能存、能读回，课程列表第二行用它。 */
class ClassNameFieldTest {
    private fun documentWith(className: String) = DemoData.makeDocument().copy(
        courses = listOf(
            Course(
                id = "C1",
                name = "传感器与智能检测技术",
                teacher = "冯江涛",
                location = "",
                colorID = "blue",
                weeks = (1..16).toList(),
                meetings = listOf(Meeting("M1", 1, 3, 4)),
                className = className,
            ),
        ),
    )

    @Test fun classNameSurvivesRoundTrip() {
        val data = StoreCodec.exporting(documentWith("DianQi2101"))
        val back = StoreCodec.importing(data).document
        assertEquals("DianQi2101", back?.courses?.first()?.className)
    }

    @Test fun emptyClassNameStaysEmpty() {
        val data = StoreCodec.exporting(documentWith(""))
        val back = StoreCodec.importing(data).document
        assertTrue(back!!.courses.first().className.isEmpty())
    }
}