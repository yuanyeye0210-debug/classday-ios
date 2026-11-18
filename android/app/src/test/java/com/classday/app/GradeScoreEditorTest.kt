package com.classday.app

import com.classday.app.core.*
import org.junit.Assert.*
import org.junit.Test

class GradeScoreEditorTest {
    @Test fun malformedRulesCannotWritePlausibleButWrongTotals() {
        val original = course()
        val scheme = original.gradeScheme!!
        val badBranches = listOf(
            emptyList(),
            listOf(emptyList()),
            listOf(listOf(GradeTerm("work", -1.0), GradeTerm("final", 2.0))),
            listOf(listOf(GradeTerm("work", 0.2), GradeTerm("final", 0.2))),
            listOf(listOf(GradeTerm("missing", 1.0))),
            listOf(listOf(GradeTerm("final", Double.NaN))),
        )
        badBranches.forEach { branches ->
            assertNull(GradeScoreEditor.applying(original.copy(gradeScheme = scheme.copy(branches = branches)),
                mapOf("work" to "80", "final" to "60")))
        }
        assertEquals(55.0, original.grade!!, 1e-8)
    }

    @Test fun retainedInvalidScoresMustBeRepairedBeforeSaving() {
        val original = course()
        val invalid = original.copy(gradeScheme = original.gradeScheme!!.copy(scores = mapOf("work" to 110.0)))
        assertNull(GradeScoreEditor.applying(invalid, mapOf("final" to "20")))
        val repaired = GradeScoreEditor.applying(invalid, mapOf("work" to "80", "final" to "20"))!!
        assertEquals(44.0, repaired.grade!!, 1e-8)
    }
    private fun course(): Course = DemoData.makeDocument().courses.first().copy(grade = 55.0,
        gradeScheme = GradeScheme(100.0, listOf(GradeComponent("work", "平时"), GradeComponent("final", "期末")),
            mapOf("work" to 70.0), listOf(listOf(GradeTerm("work", 0.4), GradeTerm("final", 0.6)))))

    @Test fun savesKnownScoresAndRecalculatesOnlyWhenComplete() {
        val original = course()
        val partial = GradeScoreEditor.applying(original, mapOf("work" to "80"))!!
        assertEquals(55.0, partial.grade!!, 1e-8)
        assertEquals(46.6666666667, FinalScorePrediction.evaluate(partial.gradeScheme!!, "final", 60.0).minimum!!, 1e-8)
        val complete = GradeScoreEditor.applying(partial, mapOf("final" to "60"))!!
        assertEquals(68.0, complete.grade!!, 1e-8)
        assertEquals(original.meetings, complete.meetings)
        assertEquals(original.gradeScheme!!.branches, complete.gradeScheme!!.branches)
        assertEquals(70.0, original.gradeScheme.scores["work"]!!, 1e-8)
    }

    @Test fun blankFieldsPreserveExistingAndZeroIsARealScore() {
        val original = course()
        assertEquals(original, GradeScoreEditor.applying(original, mapOf("work" to " ")))
        assertEquals(0.0, GradeScoreEditor.applying(original, mapOf("work" to "0"))!!.gradeScheme!!.scores["work"]!!, 1e-8)
    }

    @Test fun invalidEditsAreRejectedAtomically() {
        for (bad in listOf("NaN", "Infinity", "-1", "101", "hello")) {
            assertNull(GradeScoreEditor.applying(course(), mapOf("work" to "90", "final" to bad)))
        }
        assertNull(GradeScoreEditor.applying(course(), mapOf("missing" to "80")))
        assertNull(GradeScoreEditor.applying(course().copy(gradeScheme = null), mapOf("work" to "80")))
    }
}
