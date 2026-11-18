package com.classday.app

import com.classday.app.core.GradeComponent
import com.classday.app.core.GradeScheme
import com.classday.app.core.GradeTerm
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GradeSchemeMinimumTest {
    private val project = GradeComponent("p", "小组项目")
    private val midterm = GradeComponent("t", "期中测验")
    private val exam = GradeComponent("e1", "期末考试")
    private val retake = GradeComponent("e2", "补考")

    /** 用户给的示例：G = 0.25P + max(0.25T + 0.50E1, 0.75E1, 0.75E2)，20 分制。 */
    private fun scheme(scores: Map<String, Double>, minimums: Map<String, Double> = emptyMap()) = GradeScheme(
        scale = 20.0,
        components = listOf(project, midterm, exam, retake),
        scores = scores,
        branches = listOf(
            listOf(GradeTerm("p", 0.25), GradeTerm("t", 0.25), GradeTerm("e1", 0.50)),
            listOf(GradeTerm("p", 0.25), GradeTerm("e1", 0.75)),
            listOf(GradeTerm("p", 0.25), GradeTerm("e2", 0.75))
        ),
        minimums = minimums
    )

    @Test
    fun takesHighestBranchWhenMidtermDropped() {
        // 期中没考好：方案1 = 0.25*20+0.25*4+0.5*16 = 14；方案2 = 0.25*20+0.75*16 = 17
        val s = scheme(mapOf("p" to 20.0, "t" to 4.0, "e1" to 16.0))
        assertEquals(17.0, s.finalGrade!!, 1e-9)
        assertEquals(85.0, s.normalizedFinal!!, 1e-9)
    }

    @Test
    fun retakeCanReplaceFinal() {
        val s = scheme(mapOf("p" to 20.0, "t" to 4.0, "e1" to 10.0, "e2" to 18.0))
        // 方案1 = 5+1+5=11；方案2 = 5+7.5=12.5；方案3 = 5+13.5=18.5
        assertEquals(18.5, s.finalGrade!!, 1e-9)
    }

    @Test
    fun missingScoreSkipsBranch() {
        val s = scheme(mapOf("p" to 20.0, "e1" to 16.0))
        // 期中缺失 -> 方案1 不算；方案2 = 5+12 = 17
        assertEquals(17.0, s.finalGrade!!, 1e-9)
    }

    @Test
    fun flagsComponentBelowMinimum() {
        val s = scheme(mapOf("p" to 20.0, "e1" to 6.0), minimums = mapOf("e1" to 8.0))
        assertEquals(1, s.minimumWarnings.size)
        assertTrue(s.minimumWarnings.first().contains("期末考试"))
    }

    @Test
    fun noWarningWhenMinimumMet() {
        val s = scheme(mapOf("p" to 20.0, "e1" to 8.0), minimums = mapOf("e1" to 8.0))
        assertTrue(s.minimumWarnings.isEmpty())
    }
}