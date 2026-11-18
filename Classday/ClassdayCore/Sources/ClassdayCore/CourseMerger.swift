import Foundation

/// One group of courses that share a normalized name.
/// `courses` are in document order; `normalizedName` is the shared merge key.
public struct DuplicateGroup: Sendable, Equatable {
    public let normalizedName: String
    public let courses: [Course]

    public init(normalizedName: String, courses: [Course]) {
        self.normalizedName = normalizedName
        self.courses = courses
    }
}

/// Merge key for a course name (design §1): delete every whitespace character
/// (including fullwidth space U+3000), lowercase ASCII A–Z, and fold fullwidth
/// ASCII (U+FF01–U+FF5E) to halfwidth. No traditional/simplified conversion.
public func normalizeCourseName(_ name: String) -> String {
    var result = ""
    result.reserveCapacity(name.count)
    for scalar in name.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            continue
        }
        var value = scalar.value
        if (0xFF01...0xFF5E).contains(value) {
            value -= 0xFEE0
        }
        if (0x41...0x5A).contains(value) {
            value += 32
        }
        guard let folded = UnicodeScalar(value) else {
            continue
        }
        result.unicodeScalars.append(folded)
    }
    // 2.10.1：去掉首尾的括号/连字符等杂符。
    // 真实数据里有 "Power Conversion & Storage   (   " 这种名字。
    let junk = CharacterSet(charactersIn: "()（）[]【】{}—-_.·,、:：/\\|")
    while let first = result.unicodeScalars.first, junk.contains(first) { result.removeFirst() }
    while let last = result.unicodeScalars.last, junk.contains(last) { result.removeLast() }
    return result
}

/// 展示用的课程名：只清首尾的空格与杂符，中间不动。
public func cleanCourseDisplayName(_ name: String) -> String {
    var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let junk = CharacterSet(charactersIn: "()（）[]【】{}—-_.·,、:：/\\|")
    while let last = trimmed.unicodeScalars.last,
          junk.contains(last) || CharacterSet.whitespacesAndNewlines.contains(last) {
        trimmed.removeLast()
    }
    return trimmed
}

/// Groups courses by normalized name, keeping only groups with 2+ members.
/// Groups are ordered by first appearance; courses inside a group keep
/// document order.
public func findDuplicateGroups(courses: [Course]) -> [DuplicateGroup] {
    var order: [String] = []
    var grouped: [String: [Course]] = [:]
    for course in courses {
        let key = normalizeCourseName(course.name)
        if grouped[key] == nil {
            order.append(key)
        }
        grouped[key, default: []].append(course)
    }
    var result: [DuplicateGroup] = []
    for key in order {
        guard let members = grouped[key], members.count >= 2 else {
            continue
        }
        result.append(DuplicateGroup(normalizedName: key, courses: members))
    }
    return result
}

/// Deleted course id → survivor id, produced by `mergeDuplicateGroup`.
public typealias CourseIDRemap = [UUID: UUID]

/// Dropped meeting id → kept meeting id, produced by
/// `droppedMeetingRemap(of:)`: one entry per meeting dropped by the
/// slot dedup in `mergeDuplicateGroup`.
public typealias MeetingIDRemap = [UUID: UUID]

/// Keep review discoverable when excluding other members can produce a safe merge.
public func hasMergeableCoursePair(_ courses: [Course], context: ScheduleContext) -> Bool {
    for (index, first) in courses.enumerated() {
        for second in courses.dropFirst(index + 1) {
            if canMergeCourseSchedules([first, second], context: context) { return true }
        }
    }
    return false
}

/// The current merged course can represent only one week set and one room.
/// Slot deduplication also cannot preserve conflicting parity rules.
public func canMergeCourseSchedules(_ courses: [Course], context: ScheduleContext) -> Bool {
    guard let first = courses.first else { return true }
    guard courses.allSatisfy({ Set($0.weeks) == Set(first.weeks) && $0.location == first.location }) else {
        return false
    }
    var parityBySlot: [MeetingSlot: WeekParity] = [:]
    for course in courses {
        for meeting in course.meetings {
            let slot = MeetingSlot(weekday: meeting.weekday, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
            let parity = context.parity(for: meeting.id)
            if let existing = parityBySlot[slot], existing != parity { return false }
            parityBySlot[slot] = parity
        }
    }
    return true
}

/// Rewrites the `courseID` of every override anchored on a deleted course
/// to its survivor id (design §4). `meetingID` and all other fields are
/// untouched; overrides on unmapped course ids are returned unchanged, in
/// the same order. Pure function, no I/O.
public func remapOccurrenceOverrides(
    _ overrides: [OccurrenceOverride],
    remap: CourseIDRemap
) -> [OccurrenceOverride] {
    return overrides.map { override in
        guard let survivor = remap[override.courseID] else {
            return override
        }
        var remapped = override
        remapped.courseID = survivor
        return remapped
    }
}

/// Rewrites the `meetingID` of every override anchored on a meeting
/// dropped by the slot dedup to the kept meeting for that slot (I1).
/// `courseID` and all other fields are untouched; overrides on unmapped
/// meeting ids are returned unchanged, in the same order. Pure function,
/// no I/O. Apply after `remapOccurrenceOverrides`.
public func remapOverrideMeetingIDs(
    _ overrides: [OccurrenceOverride],
    remap: MeetingIDRemap
) -> [OccurrenceOverride] {
    return overrides.map { override in
        guard let kept = remap[override.meetingID] else {
            return override
        }
        var remapped = override
        remapped.meetingID = kept
        return remapped
    }
}

/// Rewrites the `meetingID` of every week rule anchored on a meeting
/// dropped by the slot dedup to the kept meeting for that slot (I1).
/// Rules on unmapped meeting ids are returned unchanged, in the same
/// order. Pure function, no I/O.
public func remapWeekRuleMeetingIDs(
    _ weekRules: [MeetingWeekRule],
    remap: MeetingIDRemap
) -> [MeetingWeekRule] {
    return weekRules.map { rule in
        guard let kept = remap[rule.meetingID] else {
            return rule
        }
        var remapped = rule
        remapped.meetingID = kept
        return remapped
    }
}

/// Rewrites the `courseID` of every cancellation anchored on a deleted
/// course to its survivor id (design §4). Whole-day records
/// (`courseID == nil`) and cancellations on unmapped course ids are
/// returned unchanged, in the same order. Pure function, no I/O.
public func remapClassCancellations(
    _ cancellations: [ClassCancellation],
    remap: CourseIDRemap
) -> [ClassCancellation] {
    return cancellations.map { cancellation in
        guard let courseID = cancellation.courseID, let survivor = remap[courseID] else {
            return cancellation
        }
        var remapped = cancellation
        remapped.courseID = survivor
        return remapped
    }
}

/// A meeting slot, for deduping merged meetings (design §3).
private struct MeetingSlot: Hashable {
    let weekday: Int
    let startPeriod: Int
    let endPeriod: Int
}

/// Merges one duplicate group into a single course (design §3). Pure function.
/// - Survivor: first course in document order; keeps its own `id` and its
///   `teacher` / `location` / `department` / `note` / `colorID` / `kind` /
///   `credits`. `meetings` is the union of all members' meetings, deduped by
///   `(weekday, startPeriod, endPeriod)` with every meeting keeping its
///   original `id`; `weeks` is the deduped, sorted union.
///   `reminderLeadMinutes` is the survivor's, else the first non-nil among
///   members in document order.
/// - Grade: no graded member → nil grade and scheme; exactly one distinct
///   grade value → that grade and the earliest member's scheme with it;
///   two or more distinct grade values → conflict, and `gradeSourceID` must
///   be the id of a graded member, whose grade and scheme win. A conflict
///   without a graded member's id traps (precondition failure) so the caller
///   can never merge a conflicted group without a choice.
/// - Returns the merged course plus a remap of every non-survivor id to the
///   survivor id.
public func mergeDuplicateGroup(
    _ group: DuplicateGroup,
    gradeSourceID: UUID?
) -> (course: Course, remap: CourseIDRemap) {
    precondition(!group.courses.isEmpty, "mergeDuplicateGroup: group must not be empty")
    let survivor = group.courses[0]

    // 2.10.1：合并后清掉课程名首尾的杂符。
    var merged = survivor
    merged.name = cleanCourseDisplayName(survivor.name)
    merged.meetings = dedupedMeetings(of: group.courses)
    merged.weeks = Array(Set(group.courses.flatMap(\.weeks))).sorted()
    merged.reminderLeadMinutes = group.courses.compactMap(\.reminderLeadMinutes).first
    // 2.9.9：同一门课常常分在不同教室（讲座 + 实验），合并时把所有教室都写进课程。
    var seenRooms = Set<String>()
    let rooms = group.courses
        .map { $0.location.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seenRooms.insert($0).inserted }
    if rooms.count > 1 {
        merged.location = rooms.joined(separator: " / ")
    } else if rooms.count == 1 {
        // 只有一个成员填了教室时就用那一个，不能沿用幸存者的空值。
        merged.location = rooms[0]
    }

    let (grade, gradeScheme) = mergedGrade(of: group.courses, gradeSourceID: gradeSourceID)
    merged.grade = grade
    merged.gradeScheme = gradeScheme

    var remap: CourseIDRemap = [:]
    for course in group.courses.dropFirst() {
        remap[course.id] = survivor.id
    }
    return (course: merged, remap: remap)
}

/// Dropped-meeting-id → kept-meeting-id map for one duplicate group
/// (I1). Mirrors the first-wins-per-slot rule in `dedupedMeetings`:
/// walking members in document order, the first meeting seen for a
/// `(weekday, startPeriod, endPeriod)` slot is the kept one and every
/// later meeting on that slot maps to it. Meetings on unique slots
/// produce no entry. Pure function, no I/O.
public func droppedMeetingRemap(of group: DuplicateGroup) -> MeetingIDRemap {
    var keptBySlot: [MeetingSlot: UUID] = [:]
    var remap: MeetingIDRemap = [:]
    for course in group.courses {
        for meeting in course.meetings {
            let slot = MeetingSlot(
                weekday: meeting.weekday,
                startPeriod: meeting.startPeriod,
                endPeriod: meeting.endPeriod
            )
            if let kept = keptBySlot[slot] {
                remap[meeting.id] = kept
            } else {
                keptBySlot[slot] = meeting.id
            }
        }
    }
    return remap
}

/// Union of all members' meetings in document order, deduped by slot;
/// the first meeting seen for a slot wins, keeping its original `id`.
private func dedupedMeetings(of courses: [Course]) -> [Meeting] {
    var seen: Set<MeetingSlot> = []
    var result: [Meeting] = []
    for course in courses {
        for meeting in course.meetings {
            let slot = MeetingSlot(
                weekday: meeting.weekday,
                startPeriod: meeting.startPeriod,
                endPeriod: meeting.endPeriod
            )
            guard seen.insert(slot).inserted else {
                continue
            }
            // 2.10：把来源课程自己的教室写到这一次课上，
            // 合并后各次课显示各自教室，而不是一串全教室。
            var stamped = meeting
            if stamped.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stamped.location = course.location.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result.append(stamped)
        }
    }
    return result
}

/// Grade + scheme for the merged course, per the rules in
/// `mergeDuplicateGroup`. A conflicting grade is resolved by `gradeSourceID`;
/// when that member is missing or unnamed the highest grade wins, so a stale
/// confirmation page can never trap the app (2.9.7).
private func mergedGrade(
    of courses: [Course],
    gradeSourceID: UUID?
) -> (grade: Double?, gradeScheme: GradeScheme?) {
    let graded = courses.filter { $0.grade != nil }
    guard !graded.isEmpty else {
        return (grade: nil, gradeScheme: nil)
    }
    let distinctGrades = Set(graded.compactMap(\.grade))
    if distinctGrades.count == 1 {
        let earliest = graded[0]
        return (grade: earliest.grade, gradeScheme: earliest.gradeScheme)
    }
    let chosen = graded.first(where: { $0.id == gradeSourceID })
        ?? graded.max(by: { ($0.grade ?? 0) < ($1.grade ?? 0) })!
    return (grade: chosen.grade, gradeScheme: chosen.gradeScheme)
}

// MARK: - 2.9.8 自动合并

/// 自动合并同名课程的结果。
/// `mergedGroupCount` 是这次真正被合成一门的组数；`remainingGroups` 是同名但
/// 安排冲突（周次 / 教室 / 单双周不一致）的分组，原样保留交给人工合并页。
public struct AutoMergeResult: Sendable {
    public var document: StoreDocument
    public var mergedGroupCount: Int
    public var remainingGroups: [DuplicateGroup]

    public init(document: StoreDocument, mergedGroupCount: Int, remainingGroups: [DuplicateGroup]) {
        self.document = document
        self.mergedGroupCount = mergedGroupCount
        self.remainingGroups = remainingGroups
    }
}

/// 自动合并同名课程：打开应用与每次导入之后调用，不再要求先确认。
///
/// 规则与手动合并完全一致（`mergeDuplicateGroup`）：文档顺序第一个为幸存者，
/// 周次取并集、时段去重后取并集、提醒提前量取第一个非空；成绩冲突取较高分；
/// 单次改动、单双周规则与停课记录里的引用一并改指幸存者。
/// 纯函数，无 I/O；重复调用幂等（已合并的文档再跑一次返回 0）。
public func autoMergeDuplicateCourses(_ document: StoreDocument) -> AutoMergeResult {
    var current = document
    var mergedCount = 0

    while true {
        let groups = findDuplicateGroups(courses: current.courses)
        // 2.9.9：只看课程名。同一门课分在不同教室或不同周次，也并成一门；
        // 教室全部写进课程卡片，周次与时段取并集。
        guard let target = groups.first(where: { $0.courses.count > 1 }) else {
            return AutoMergeResult(
                document: current,
                mergedGroupCount: mergedCount,
                remainingGroups: groups.filter { $0.courses.count > 1 }
            )
        }
        let (course, remap) = mergeDuplicateGroup(target, gradeSourceID: autoGradeSource(target))
        let meetingRemap = droppedMeetingRemap(of: target)

        var courses = current.courses.filter { remap[$0.id] == nil }
        if let index = courses.firstIndex(where: { $0.id == course.id }) {
            courses[index] = course
        } else {
            courses.append(course)
        }
        var semester = current.semester
        semester.cancellations = remapClassCancellations(semester.cancellations, remap: remap)

        current.courses = courses
        current.overrides = remapOverrideMeetingIDs(
            remapOccurrenceOverrides(current.overrides, remap: remap),
            remap: meetingRemap
        )
        current.weekRules = remapWeekRuleMeetingIDs(current.weekRules, remap: meetingRemap)
        current.semester = semester
        mergedCount += 1
    }
}

/// 自动合并时选哪一条成绩来源：无冲突给第一个有成绩的成员，冲突给分数最高的成员。
public func autoGradeSource(_ group: DuplicateGroup) -> UUID? {
    let graded = group.courses.filter { $0.grade != nil }
    guard !graded.isEmpty else { return nil }
    if Set(graded.compactMap(\.grade)).count <= 1 { return graded.first?.id }
    return graded.max(by: { ($0.grade ?? 0) < ($1.grade ?? 0) })?.id
}