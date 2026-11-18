package com.classday.app.core

/** Validate score entry without changing the rule, course schedule or blank existing scores. */
object GradeScoreEditor {
    fun applying(course: Course, entries: Map<String, String>): Course? {
        val scheme = course.gradeScheme ?: return null
        if (!scheme.scale.isFinite() || scheme.scale <= 0) return null
        val ids = scheme.components.map { it.id }.toSet()
        if (ids.size != scheme.components.size || entries.keys.any { it !in ids }) return null
        if (scheme.branches.isEmpty() || scheme.branches.any { branch ->
            branch.isEmpty() || branch.any { !it.weight.isFinite() || it.weight < 0 || it.componentID !in ids } ||
                kotlin.math.abs(branch.sumOf { it.weight } - 1) > 1e-6
        }) return null
        val scores = scheme.scores.toMutableMap()
        for ((id, raw) in entries) {
            // Blank means unchanged, so an accidental empty field cannot erase a grade.
            if (raw.isBlank()) continue
            val score = raw.trim().toDoubleOrNull() ?: return null
            if (!score.isFinite() || score < 0 || score > scheme.scale) return null
            scores[id] = score
        }
        if (scores.any { (id, score) -> id in ids && (!score.isFinite() || score < 0 || score > scheme.scale) }) return null
        val updated = scheme.copy(scores = scores)
        val normalized = updated.normalizedFinal
        if (normalized != null && (!normalized.isFinite() || normalized !in 0.0..100.0)) return null
        return course.copy(gradeScheme = updated, grade = normalized ?: course.grade)
    }
}
