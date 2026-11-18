package com.classday.app.core

enum class PredictionStatus { required, alreadyReached, impossible, missingScores, invalidRule }
data class FinalScoreResult(val status: PredictionStatus, val minimum: Double? = null)

/** Read-only what-if calculation. The selected final component's recorded score is ignored. */
object FinalScorePrediction {
    fun evaluate(scheme: GradeScheme, finalComponentID: String, targetPercent: Double): FinalScoreResult {
        fun invalid() = FinalScoreResult(PredictionStatus.invalidRule)
        val ids = scheme.components.map { it.id }.toSet()
        if (!scheme.scale.isFinite() || scheme.scale <= 0 || !targetPercent.isFinite() ||
            targetPercent !in 0.0..100.0 || finalComponentID !in ids || ids.size != scheme.components.size ||
            scheme.branches.isEmpty()) return invalid()
        val target = targetPercent / 100 * scheme.scale
        var best = Double.POSITIVE_INFINITY
        var missing = false
        for (branch in scheme.branches) {
            if (branch.isEmpty() || branch.any { !it.weight.isFinite() || it.weight < 0 || it.componentID !in ids } ||
                kotlin.math.abs(branch.sumOf { it.weight } - 1) > 1e-6) return invalid()
            var known = 0.0
            var finalWeight = 0.0
            for (term in branch) {
                if (term.weight == 0.0) continue
                if (term.componentID == finalComponentID) { finalWeight += term.weight; continue }
                val score = scheme.scores[term.componentID]
                if (score == null) { missing = true; continue }
                if (!score.isFinite() || score < 0 || score > scheme.scale) return invalid()
                known += term.weight * score
            }
            if (!known.isFinite()) return invalid()
            val needed = when {
                known >= target -> 0.0
                finalWeight > 0 -> (target - known) / finalWeight
                else -> Double.POSITIVE_INFINITY
            }
            best = minOf(best, needed)
        }
        // Do not present an exact minimum while another algorithm has unrecorded inputs.
        if (missing) return FinalScoreResult(PredictionStatus.missingScores)
        if (best <= 0) return FinalScoreResult(PredictionStatus.alreadyReached, 0.0)
        if (best > scheme.scale + scheme.scale * 1e-10) return FinalScoreResult(PredictionStatus.impossible)
        return FinalScoreResult(PredictionStatus.required, best.coerceAtMost(scheme.scale))
    }
}
