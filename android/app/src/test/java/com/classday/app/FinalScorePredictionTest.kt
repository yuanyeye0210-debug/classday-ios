package com.classday.app

import com.classday.app.core.*
import org.junit.Assert.*
import org.junit.Test

class FinalScorePredictionTest {
    private fun scheme(scale: Double = 100.0, score: Double = 80.0) = GradeScheme(scale,
        listOf(GradeComponent("work", "平时"), GradeComponent("final", "期末")),
        mapOf("work" to score), listOf(listOf(GradeTerm("work", 0.4), GradeTerm("final", 0.6))))

    @Test fun passAndTargetUseExistingScoresWithoutMutation() {
        val rule = scheme()
        assertEquals(46.6666666667, FinalScorePrediction.evaluate(rule, "final", 60.0).minimum!!, 1e-8)
        assertEquals(80.0, FinalScorePrediction.evaluate(rule, "final", 80.0).minimum!!, 1e-8)
        assertEquals(mapOf("work" to 80.0), rule.scores)
        assertEquals(46.6666666667, FinalScorePrediction.evaluate(rule.copy(scores = rule.scores + ("final" to 1.0)), "final", 60.0).minimum!!, 1e-8)
    }

    @Test fun alreadyReachedImpossibleAndExactMaximum() {
        assertEquals(PredictionStatus.alreadyReached, FinalScorePrediction.evaluate(scheme(), "final", 30.0).status)
        assertEquals(PredictionStatus.impossible, FinalScorePrediction.evaluate(scheme(), "final", 100.0).status)
        assertEquals(100.0, FinalScorePrediction.evaluate(scheme(), "final", 92.0).minimum!!, 1e-8)
        assertEquals(PredictionStatus.alreadyReached, FinalScorePrediction.evaluate(scheme(), "final", 0.0).status)
    }

    @Test fun nonHundredScaleAndBestOfAlgorithms() {
        val rule = scheme(20.0, 16.0)
        assertEquals(9.3333333333, FinalScorePrediction.evaluate(rule, "final", 60.0).minimum!!, 1e-8)
        val multi = rule.copy(branches = rule.branches + listOf(listOf(GradeTerm("final", 1.0))))
        assertEquals(9.3333333333, FinalScorePrediction.evaluate(multi, "final", 60.0).minimum!!, 1e-8)
        val constant = rule.copy(branches = rule.branches + listOf(listOf(GradeTerm("work", 1.0))))
        assertEquals(PredictionStatus.alreadyReached, FinalScorePrediction.evaluate(constant, "final", 60.0).status)
    }

    @Test fun missingOrInvalidDataNeverAssumesZero() {
        assertEquals(PredictionStatus.missingScores, FinalScorePrediction.evaluate(scheme().copy(scores = emptyMap()), "final", 60.0).status)
        for (bad in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 101.0)) {
            assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme(score = bad), "final", 60.0).status)
            assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme(), "final", bad).status)
        }
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme(), "missing", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme().copy(branches = listOf(listOf(GradeTerm("final", -1.0)))), "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme().copy(branches = listOf(listOf(GradeTerm("final", 0.5)))), "final", 60.0).status)
    }

    @Test fun incompleteAlgorithmBlocksExactMinimumFromCompleteAlgorithm() {
        // 第二条算法只用期末分即可算出结果，但第一条算法缺平时成绩时不能给出精确最低分。
        val rule = scheme().copy(scores = emptyMap(), branches = listOf(
            listOf(GradeTerm("work", 0.4), GradeTerm("final", 0.6)),
            listOf(GradeTerm("final", 1.0)),
        ))
        assertEquals(PredictionStatus.missingScores, FinalScorePrediction.evaluate(rule, "final", 60.0).status)
        // 零权重分项不要求录分，也不应把规则误判为缺成绩。
        val zeroWeight = rule.copy(branches = listOf(listOf(GradeTerm("work", 0.0), GradeTerm("final", 1.0))))
        assertEquals(60.0, FinalScorePrediction.evaluate(zeroWeight, "final", 60.0).minimum!!, 1e-8)
    }

    @Test fun weightsMustBeDecimalFractionsNotPercentages() {
        // 权重按 0–1 小数录入（每条合计为 1，即 100%）；30/70 这类百分数应按无效规则拒绝。
        val decimal = scheme().copy(branches = listOf(listOf(GradeTerm("work", 0.3), GradeTerm("final", 0.7))))
        assertEquals(51.4285714286, FinalScorePrediction.evaluate(decimal, "final", 60.0).minimum!!, 1e-8)
        val percent = scheme().copy(branches = listOf(listOf(GradeTerm("work", 30.0), GradeTerm("final", 70.0))))
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(percent, "final", 60.0).status)
    }

    @Test fun structurallyInvalidRulesAreRejected() {
        val duplicate = scheme().copy(components = listOf(
            GradeComponent("work", "平时"), GradeComponent("work", "平时二"), GradeComponent("final", "期末")))
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(duplicate, "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme().copy(branches = emptyList()), "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme().copy(branches = listOf(emptyList())), "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme().copy(
            branches = listOf(listOf(GradeTerm("unknown", 1.0)))), "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme(scale = 0.0), "final", 60.0).status)
        assertEquals(PredictionStatus.invalidRule, FinalScorePrediction.evaluate(scheme(scale = Double.NaN), "final", 60.0).status)
    }
}
