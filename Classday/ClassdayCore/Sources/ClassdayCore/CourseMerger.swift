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
    return result
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

    var merged = survivor
    merged.meetings = dedupedMeetings(of: group.courses)
    merged.weeks = Array(Set(group.courses.flatMap(\.weeks))).sorted()
    merged.reminderLeadMinutes = group.courses.compactMap(\.reminderLeadMinutes).first

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
            result.append(meeting)
        }
    }
    return result
}

/// Grade + scheme for the merged course, per the rules in
/// `mergeDuplicateGroup`. Traps on an unresolved grade conflict.
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
    precondition(
        gradeSourceID != nil && graded.contains(where: { $0.id == gradeSourceID }),
        "mergeDuplicateGroup: grade conflict requires gradeSourceID of a graded member"
    )
    let chosen = graded.first(where: { $0.id == gradeSourceID })!
    return (grade: chosen.grade, gradeScheme: chosen.gradeScheme)
}
