package com.classday.app.core

/**
 * 2.9.8：自动合并同名课程的结果。
 *
 * - [mergedGroups]：这次真正被合成一门的组数（0 表示没有可自动合并的）。
 * - [remainingGroups]：同名但安排冲突（周次、教室或单双周不一致）的分组，
 *   原样保留，仍然走人工合并页，不会被强行并成一门。
 */
data class AutoMergeResult(
    val document: StoreDocument,
    val mergedGroups: Int,
    val remainingGroups: List<DuplicateGroup>,
)

/**
 * 自动合并同名课程：导入或打开应用时直接合并，不再要求先确认。
 *
 * 规则与手动合并完全一致（见 [applyMerge]）：以文档顺序第一个为幸存者，
 * 周次取并集、时段去重后取并集、提醒提前量取第一个非空；
 * 成绩冲突时取**较高**的那一位，避免任何一家被静默丢掉；
 * 单次改动（overrides）、单双周规则、停课记录里的课程/时段引用一并改指幸存者。
 *
 * 纯计算，不碰 Android API，JVM 单测可直接覆盖。重复调用是幂等的：
 * 已经合并过的文档再跑一次返回 mergedGroups = 0。
 */
fun autoMergeDuplicateCourses(document: StoreDocument): AutoMergeResult {
    var current = document
    var mergedCount = 0

    // 每轮只做一个分组，做完重新分组：合并会改变课程集合，索引不能复用。
    while (true) {
        val groups = findDuplicateGroups(current.courses)
        // 2.9.9：只看课程名。同一门课分在不同教室、不同周次，也并成一门；
        // 教室全部写进课程卡片，周次与时段取并集，不再要求"安排完全一致"。
        val target = groups.firstOrNull { group -> group.courses.size > 1 }
        if (target == null) {
            return AutoMergeResult(current, mergedCount, groups.filter { it.courses.size > 1 })
        }
        val next = applyMerge(current, target, autoGradeSource(target)) ?: run {
            // 理论上不会到这里（已确认可合并）；保守起见停下，把剩下的交给人工页。
            return AutoMergeResult(current, mergedCount, groups.filter { it.courses.size > 1 })
        }
        current = next
        mergedCount += 1
    }
}

/**
 * 自动合并时选哪一条成绩来源：没有冲突时给第一个有成绩的成员，
 * 冲突时给分数最高的成员（与 iOS 合并页「选不到就取较高分」同一口径）。
 */
internal fun autoGradeSource(group: DuplicateGroup): String? {
    val graded = group.courses.filter { it.grade != null }
    if (graded.isEmpty()) return null
    return if (graded.mapNotNull { it.grade }.toSet().size <= 1) {
        graded.first().id
    } else {
        graded.maxByOrNull { it.grade ?: 0.0 }?.id
    }
}
