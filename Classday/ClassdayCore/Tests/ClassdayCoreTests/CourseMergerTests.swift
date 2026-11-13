import Foundation
import XCTest
import ClassdayCore

/// Task 1 (merge-duplicate-courses): name normalization + duplicate grouping.
/// Tests written first (TDD); implementation is `CourseMerger.swift`.
final class CourseMergerTests: XCTestCase {
    func testMergeScheduleGuardPreservesWeeksRoomsAndConflictingParity() {
        let monday = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let wednesday = makeMeeting(weekday: 3, startPeriod: 3, endPeriod: 4)
        let first = makeCourse(name: "数学", meetings: [monday])
        let same = makeCourse(name: "数学", weeks: [2, 1], meetings: [wednesday])
        XCTAssertTrue(canMergeCourseSchedules([first, same], context: .empty))
        var otherWeeks = same
        otherWeeks.weeks = [3, 4]
        XCTAssertFalse(canMergeCourseSchedules([first, otherWeeks], context: .empty))
        var otherRoom = same
        otherRoom.location = "实验楼"
        XCTAssertFalse(canMergeCourseSchedules([first, otherRoom], context: .empty))
        otherRoom.location = ""
        XCTAssertFalse(canMergeCourseSchedules([first, otherRoom], context: .empty))
        let sameSlot = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let duplicate = makeCourse(name: "数学", meetings: [sameSlot])
        let odd = MeetingWeekRule(meetingID: monday.id, parity: .odd)
        let even = MeetingWeekRule(meetingID: sameSlot.id, parity: .even)
        XCTAssertFalse(canMergeCourseSchedules([first, duplicate], context: ScheduleContext(weekRules: [odd, even])))
        XCTAssertFalse(canMergeCourseSchedules([first, duplicate], context: ScheduleContext(weekRules: [odd])))
        XCTAssertTrue(canMergeCourseSchedules([first, duplicate], context: ScheduleContext(weekRules: [odd, MeetingWeekRule(meetingID: sameSlot.id, parity: .odd)])))
        XCTAssertTrue(canMergeCourseSchedules([first, same], context: ScheduleContext(weekRules: [odd, MeetingWeekRule(meetingID: wednesday.id, parity: .even)])))
    }

    private func makeCourse(
        name: String,
        teacher: String = "张老师",
        location: String = "教学楼 101",
        weeks: [Int] = [1, 2],
        meetings: [Meeting] = [],
        reminderLeadMinutes: Int? = nil,
        grade: Double? = nil,
        gradeScheme: GradeScheme? = nil
    ) -> Course {
        Course(
            id: UUID(),
            name: name,
            teacher: teacher,
            location: location,
            colorID: "blue",
            weeks: weeks,
            meetings: meetings,
            reminderLeadMinutes: reminderLeadMinutes,
            grade: grade,
            gradeScheme: gradeScheme
        )
    }

    private func makeMeeting(weekday: Int, startPeriod: Int, endPeriod: Int) -> Meeting {
        Meeting(id: UUID(), weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod)
    }

    func testNormalizeTrimsAndRemovesAllWhitespace() {
        XCTAssertEqual(normalizeCourseName("  高等数学\u{3000} "), "高等数学")
        XCTAssertEqual(normalizeCourseName("高 等 数 学"), "高等数学")
        XCTAssertEqual(normalizeCourseName("高等数学"), "高等数学")
    }

    func testNormalizeLowercasesASCIIAndFoldsFullwidth() {
        XCTAssertEqual(normalizeCourseName("ＡBC"), "abc")
        XCTAssertEqual(normalizeCourseName("Ａ（Ｂ）"), "a(b)")
        XCTAssertEqual(normalizeCourseName("Math 101"), "math101")
    }

    func testNormalizeDoesNotConvertTraditional() {
        XCTAssertEqual(normalizeCourseName("發"), "發")
        XCTAssertEqual(normalizeCourseName("發 展 經 濟 學"), "發展經濟學")
    }

    func testFindGroupsSameNameDifferentTeachers() {
        let first = makeCourse(name: "高等数学", teacher: "张老师")
        let second = makeCourse(name: "高等数学", teacher: "李老师")
        let groups = findDuplicateGroups(courses: [first, second])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].normalizedName, "高等数学")
        XCTAssertEqual(groups[0].courses, [first, second])
    }

    func testFindGroupsGroupsByNormalizedName() {
        let first = makeCourse(name: "高等数学")
        let second = makeCourse(name: " 高等数学\u{3000}")
        let third = makeCourse(name: "高等數学")
        let groups = findDuplicateGroups(courses: [first, second, third])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].normalizedName, "高等数学")
        XCTAssertEqual(groups[0].courses, [first, second])
    }

    func testFindGroupsIgnoresUniqueNames() {
        let courses = [
            makeCourse(name: "高等数学"),
            makeCourse(name: "线性代数"),
        ]
        XCTAssertEqual(findDuplicateGroups(courses: courses), [])
        XCTAssertEqual(findDuplicateGroups(courses: []), [])
    }

    func testFindGroupsKeepsDocumentOrder() {
        let b1 = makeCourse(name: "线性代数", teacher: "王老师")
        let a1 = makeCourse(name: "高等数学", teacher: "张老师")
        let b2 = makeCourse(name: "线性代数", teacher: "赵老师")
        let a2 = makeCourse(name: "高等数学", teacher: "李老师")
        let unique = makeCourse(name: "大学物理")
        let groups = findDuplicateGroups(courses: [b1, a1, b2, a2, unique])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { $0.normalizedName }, ["线性代数", "高等数学"])
        XCTAssertEqual(groups[0].courses, [b1, b2])
        XCTAssertEqual(groups[1].courses, [a1, a2])
    }

    // MARK: - Task 2: merge + grade conflict model

    func testMergeKeepsSurvivorIDAndUnionsMeetings() {
        let sharedFirst = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        // Same (weekday, startPeriod, endPeriod) slot, different meeting id.
        let sharedSecond = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let other = makeMeeting(weekday: 3, startPeriod: 3, endPeriod: 4)
        let first = makeCourse(name: "高等数学", teacher: "张老师", meetings: [sharedFirst])
        let second = makeCourse(name: "高等数学", teacher: "李老师", meetings: [sharedSecond, other])
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertEqual(merged.course.id, first.id)
        XCTAssertEqual(merged.course.name, first.name)
        XCTAssertEqual(merged.course.teacher, "张老师")
        XCTAssertEqual(merged.course.meetings, [sharedFirst, other])
        // Survivor has no reminder; first non-nil among members wins.
        let withReminder = makeCourse(
            name: "高等数学", meetings: [sharedFirst], reminderLeadMinutes: nil)
        let withReminderSecond = makeCourse(
            name: "高等数学", meetings: [other], reminderLeadMinutes: 15)
        let reminderGroup = DuplicateGroup(
            normalizedName: "高等数学", courses: [withReminder, withReminderSecond])
        XCTAssertEqual(
            mergeDuplicateGroup(reminderGroup, gradeSourceID: nil).course.reminderLeadMinutes, 15)
        let survivorReminder = makeCourse(
            name: "高等数学", meetings: [sharedFirst], reminderLeadMinutes: 10)
        let survivorReminderGroup = DuplicateGroup(
            normalizedName: "高等数学", courses: [survivorReminder, withReminderSecond])
        XCTAssertEqual(
            mergeDuplicateGroup(survivorReminderGroup, gradeSourceID: nil).course.reminderLeadMinutes,
            10)
    }

    func testMergeUnionsWeeksSorted() {
        let first = makeCourse(name: "高等数学", weeks: [1, 2])
        let second = makeCourse(name: "高等数学", weeks: [2, 3])
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertEqual(merged.course.weeks, [1, 2, 3])
    }

    func testMergeKeepsSingleGrade() {
        let scheme = GradeScheme(scale: 20)
        let first = makeCourse(name: "高等数学")
        let second = makeCourse(name: "高等数学", grade: 85, gradeScheme: scheme)
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertEqual(merged.course.grade, 85)
        XCTAssertEqual(merged.course.gradeScheme, scheme)
    }

    func testMergeSameGradeKeepsEarliestScheme() {
        let earliestScheme = GradeScheme(scale: 100)
        let laterScheme = GradeScheme(scale: 20)
        let first = makeCourse(name: "高等数学", grade: 90, gradeScheme: earliestScheme)
        let second = makeCourse(name: "高等数学", grade: 90, gradeScheme: laterScheme)
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertEqual(merged.course.grade, 90)
        XCTAssertEqual(merged.course.gradeScheme, earliestScheme)
    }

    func testMergeNoGradeStaysNil() {
        let first = makeCourse(name: "高等数学")
        let second = makeCourse(name: "高等数学")
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertNil(merged.course.grade)
        XCTAssertNil(merged.course.gradeScheme)
    }

    func testMergeGradeConflictRequiresChoice() {
        let firstScheme = GradeScheme(scale: 100)
        let secondScheme = GradeScheme(scale: 20)
        let first = makeCourse(name: "高等数学", grade: 80, gradeScheme: firstScheme)
        let second = makeCourse(name: "高等数学", grade: 90, gradeScheme: secondScheme)
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        // NOTE: calling mergeDuplicateGroup(group, gradeSourceID: nil) here
        // traps by design (precondition failure) and would terminate the test
        // runner, so the nil case is intentionally not invoked in-process;
        // the precondition is the guard. The choice paths below are verified.
        let chosenSecond = mergeDuplicateGroup(group, gradeSourceID: second.id)
        XCTAssertEqual(chosenSecond.course.grade, 90)
        XCTAssertEqual(chosenSecond.course.gradeScheme, secondScheme)
        let chosenFirst = mergeDuplicateGroup(group, gradeSourceID: first.id)
        XCTAssertEqual(chosenFirst.course.grade, 80)
        XCTAssertEqual(chosenFirst.course.gradeScheme, firstScheme)
    }

    // MARK: - Task 3: remap overrides and cancellations

    private func makeOverride(courseID: UUID, meetingID: UUID, week: Int = 3) -> OccurrenceOverride {
        OccurrenceOverride(courseID: courseID, meetingID: meetingID, week: week, kind: .cancelled)
    }

    private func makeCancellation(courseID: UUID?, date: String = "2026-11-12") -> ClassCancellation {
        ClassCancellation(
            id: UUID(), date: date, courseID: courseID,
            courseName: "高等数学", scope: "all", reason: "停课")
    }

    func testRemapOverridesRewritesDeletedCourseIDs() {
        let survivor = UUID()
        let deleted = UUID()
        let other = UUID()
        let deletedMeeting = UUID()
        let survivorMeeting = UUID()
        let otherMeeting = UUID()
        let overrides = [
            makeOverride(courseID: deleted, meetingID: deletedMeeting),
            makeOverride(courseID: survivor, meetingID: survivorMeeting),
            makeOverride(courseID: other, meetingID: otherMeeting),
        ]
        let remap: CourseIDRemap = [deleted: survivor]

        let remapped = remapOccurrenceOverrides(overrides, remap: remap)

        XCTAssertEqual(remapped.count, 3)
        // Deleted course id rewrites to the survivor; meetingID and the
        // rest of the record are untouched.
        XCTAssertEqual(remapped[0].courseID, survivor)
        XCTAssertEqual(remapped[0].meetingID, deletedMeeting)
        XCTAssertEqual(remapped[0].week, 3)
        XCTAssertEqual(remapped[0].kind, .cancelled)
        XCTAssertEqual(remapped[0].id, overrides[0].id)
        // Order is preserved and unmapped records are identical.
        XCTAssertEqual(remapped[1], overrides[1])
        XCTAssertEqual(remapped[2], overrides[2])
    }

    func testRemapOverridesLeavesUnmappedUntouched() {
        let survivor = UUID()
        let deleted = UUID()
        let unrelated = UUID()
        let overrides = [
            makeOverride(courseID: survivor, meetingID: UUID()),
            makeOverride(courseID: unrelated, meetingID: UUID()),
        ]
        let remap: CourseIDRemap = [deleted: survivor]

        XCTAssertEqual(remapOccurrenceOverrides(overrides, remap: remap), overrides)
        XCTAssertEqual(remapOccurrenceOverrides(overrides, remap: [:]), overrides)
        XCTAssertEqual(remapOccurrenceOverrides([], remap: remap), [])
    }

    func testRemapCancellationsRewritesDeletedCourseIDs() {
        let survivor = UUID()
        let deleted = UUID()
        let other = UUID()
        let cancellations = [
            makeCancellation(courseID: deleted),
            makeCancellation(courseID: survivor),
            makeCancellation(courseID: other),
        ]
        let remap: CourseIDRemap = [deleted: survivor]

        let remapped = remapClassCancellations(cancellations, remap: remap)

        XCTAssertEqual(remapped.count, 3)
        XCTAssertEqual(remapped[0].courseID, survivor)
        XCTAssertEqual(remapped[0].date, "2026-11-12")
        XCTAssertEqual(remapped[0].courseName, "高等数学")
        XCTAssertEqual(remapped[0].scope, "all")
        XCTAssertEqual(remapped[0].reason, "停课")
        XCTAssertEqual(remapped[0].id, cancellations[0].id)
        XCTAssertEqual(remapped[1], cancellations[1])
        XCTAssertEqual(remapped[2], cancellations[2])
    }

    func testRemapCancellationsLeavesNilCourseIDUntouched() {
        let survivor = UUID()
        let deleted = UUID()
        let unrelated = UUID()
        let cancellations = [
            makeCancellation(courseID: nil),
            makeCancellation(courseID: unrelated),
        ]
        let remap: CourseIDRemap = [deleted: survivor]

        // Whole-day record (nil courseID) and unmapped records stay identical.
        XCTAssertEqual(remapClassCancellations(cancellations, remap: remap), cancellations)
        XCTAssertEqual(remapClassCancellations([], remap: remap), [])
    }

    func testMergeRemapMapsDeletedIDsToSurvivor() {
        let first = makeCourse(name: "高等数学")
        let second = makeCourse(name: "高等数学")
        let third = makeCourse(name: "高等数学")
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second, third])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)

        XCTAssertEqual(merged.course.id, first.id)
        XCTAssertEqual(merged.remap, [second.id: first.id, third.id: first.id])
        XCTAssertNil(merged.remap[first.id])
    }

    // MARK: - Task 7 fix (I1): dropped duplicate-slot meetings orphan overrides

    func testDroppedMeetingOverrideLandsOnKeptMeeting() {
        let kept = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let dropped = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let other = makeMeeting(weekday: 3, startPeriod: 3, endPeriod: 4)
        let first = makeCourse(name: "高等数学", meetings: [kept])
        let second = makeCourse(name: "高等数学", meetings: [dropped, other])
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let merged = mergeDuplicateGroup(group, gradeSourceID: nil)
        XCTAssertEqual(merged.course.meetings, [kept, other])

        // The dropped meeting's id maps to the kept meeting for its slot.
        let meetingRemap = droppedMeetingRemap(of: group)
        XCTAssertEqual(meetingRemap, [dropped.id: kept.id])

        // The review's concrete case: week 3 on the second copy was cancelled.
        let cancelled = makeOverride(courseID: second.id, meetingID: dropped.id, week: 3)
        let keptOverride = makeOverride(courseID: first.id, meetingID: kept.id, week: 4)
        let unrelated = makeOverride(courseID: UUID(), meetingID: UUID(), week: 3)
        let overrides = [cancelled, keptOverride, unrelated]

        let remapped = remapOverrideMeetingIDs(
            remapOccurrenceOverrides(overrides, remap: merged.remap),
            remap: meetingRemap
        )

        XCTAssertEqual(remapped.count, 3)
        XCTAssertEqual(remapped[0].courseID, first.id)
        XCTAssertEqual(remapped[0].meetingID, kept.id)
        XCTAssertEqual(remapped[0].week, 3)
        XCTAssertEqual(remapped[0].kind, .cancelled)
        XCTAssertEqual(remapped[0].id, cancelled.id)
        XCTAssertEqual(remapped[1], keptOverride)
        XCTAssertEqual(remapped[2], unrelated)
    }

    func testDroppedMeetingWeekRuleLandsOnKeptMeeting() {
        let kept = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let dropped = makeMeeting(weekday: 1, startPeriod: 1, endPeriod: 2)
        let first = makeCourse(name: "高等数学", meetings: [kept])
        let second = makeCourse(name: "高等数学", meetings: [dropped])
        let group = DuplicateGroup(normalizedName: "高等数学", courses: [first, second])

        let meetingRemap = droppedMeetingRemap(of: group)
        XCTAssertEqual(meetingRemap, [dropped.id: kept.id])

        let rules = [
            MeetingWeekRule(meetingID: dropped.id, parity: .odd),
            MeetingWeekRule(meetingID: kept.id, parity: .even),
            MeetingWeekRule(meetingID: UUID(), parity: .odd),
        ]

        let remapped = remapWeekRuleMeetingIDs(rules, remap: meetingRemap)

        XCTAssertEqual(remapped[0].meetingID, kept.id)
        XCTAssertEqual(remapped[0].parity, .odd)
        XCTAssertEqual(remapped[1], rules[1])
        XCTAssertEqual(remapped[2], rules[2])
        XCTAssertEqual(remapWeekRuleMeetingIDs(rules, remap: [:]), rules)
        XCTAssertEqual(remapWeekRuleMeetingIDs([], remap: meetingRemap), [])
    }
}
