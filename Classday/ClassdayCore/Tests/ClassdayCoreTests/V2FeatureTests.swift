import XCTest
import ClassdayCore

final class V2FeatureTests: XCTestCase {
    private let calendar = TestSupport.calendar()

    func testSevenThemesAndSaverDowngrade() {
        XCTAssertEqual(ClassdayThemes.all.count, 7)
        XCTAssertEqual(Set(ClassdayThemes.all.map(\.id)).count, 7)
        XCTAssertEqual(ClassdayThemes.theme(id: "missing").id, "neon")
        XCTAssertEqual(ClassdayThemes.effectiveTier(selected: .high, lowPower: true, reduceMotion: false), .saver)
        XCTAssertEqual(ClassdayThemes.effectiveTier(selected: .high, lowPower: false, reduceMotion: true), .saver)
        XCTAssertEqual(ClassdayThemes.effectiveTier(selected: .balanced, lowPower: false, reduceMotion: false), .balanced)
        XCTAssertFalse(ClassdayThemes.all.contains { $0.name.contains("Watch") })
    }

    func testOddWeekAndSingleCancellation() {
        var document = DemoData.makeDocument()
        document = TimetableLibrary.settingParity(document, meetingID: DemoData.ID.calculusMonday, parity: .odd)
        let odd = ScheduleEngine.occurrences(
            inWeek: 9,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        )
        XCTAssertTrue(odd.contains { $0.meetingID == DemoData.ID.calculusMonday && $0.parityLabel == "单周" })
        let even = ScheduleEngine.occurrences(
            inWeek: 10,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        )
        XCTAssertFalse(even.contains { $0.meetingID == DemoData.ID.calculusMonday })
        document = TimetableLibrary.overriding(
            document,
            with: OccurrenceOverride(courseID: DemoData.ID.english, meetingID: DemoData.ID.englishMonday, week: 9, kind: .cancelled)
        )
        let cancelled = ScheduleEngine.occurrences(
            inWeek: 9,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar,
            context: document.scheduleContext
        )
        XCTAssertFalse(cancelled.contains { $0.meetingID == DemoData.ID.englishMonday })
        XCTAssertTrue(cancelled.contains { $0.meetingID == DemoData.ID.englishThursday })
        let restored = TimetableLibrary.clearingOverride(document, courseID: DemoData.ID.english, meetingID: DemoData.ID.englishMonday, week: 9)
        XCTAssertTrue(
            ScheduleEngine.occurrences(inWeek: 9, courses: restored.courses, semester: restored.semester, calendar: calendar, context: restored.scheduleContext)
                .contains { $0.meetingID == DemoData.ID.englishMonday }
        )
    }

    func testDelayDoesNotRewriteTheTerm() {
        var document = DemoData.makeDocument()
        document = TimetableLibrary.overriding(
            document,
            with: OccurrenceOverride(courseID: DemoData.ID.calculus, meetingID: DemoData.ID.calculusMonday, week: 10, kind: .delayed, delayMinutes: 10)
        )
        let week = ScheduleEngine.occurrences(inWeek: 10, courses: document.courses, semester: document.semester, calendar: calendar, context: document.scheduleContext)
        let delayed = week.first { $0.meetingID == DemoData.ID.calculusMonday }
        let other = ScheduleEngine.occurrences(inWeek: 11, courses: document.courses, semester: document.semester, calendar: calendar, context: document.scheduleContext)
            .first { $0.meetingID == DemoData.ID.calculusMonday }
        XCTAssertEqual(calendar.component(.minute, from: delayed!.start), 10)
        XCTAssertEqual(calendar.component(.minute, from: other!.start), 0)
    }

    func testICSAndFenixImportExams() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:高等数学
        LOCATION:教学楼 A · 301
        DTSTART:20261102T080000
        DTEND:20261102T094000
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:高等数学考试
        LOCATION:教学楼 A · 301
        DTSTART:20270112T090000
        DTEND:20270112T110000
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:作业：习题
        DTSTART:20261120T180000
        DTEND:20261120T180000
        END:VEVENT
        END:VCALENDAR
        """
        let imported = ICSImporter.parse(ics, calendar: calendar)
        XCTAssertEqual(imported.courses.map(\.name), ["高等数学"])
        XCTAssertEqual(imported.exams.count, 1)
        XCTAssertEqual(imported.homework.count, 1)

        let classes = Data(#"[{"course":{"name":"程序设计"},"location":{"name":"机房 2"},"start":"2026-11-02T14:00:00","end":"2026-11-02T15:40:00"}]"#.utf8)
        let evaluations = Data(#"[{"name":"Exame","type":"EXAM","start":"2027-01-15T09:00:00","end":"2027-01-15T11:00:00","courses":[{"name":"程序设计"}],"rooms":[{"name":"机房 2"}]}]"#.utf8)
        let decoded = FenixCalendar.decodeClasses(classes)
        XCTAssertEqual(decoded.map(\.courseName), ["程序设计"])
        let fenixCourses = FenixCalendar.courses(from: decoded, calendar: calendar)
        XCTAssertEqual(fenixCourses.map(\.name), ["程序设计"])
        XCTAssertEqual(FenixCalendar.exams(from: FenixCalendar.decodeEvaluations(evaluations), calendar: calendar).count, 1)
    }

    func testShareRoundTripAndTimetableSwitch() {
        let document = DemoData.makeDocument()
        let payload = ShareCodec.decode(ShareCodec.encode(document))
        XCTAssertEqual(payload?.courses.count, document.courses.count)
        XCTAssertEqual(payload?.semester.shortName, document.semester.shortName)
        let backupID = UUID(uuidString: "00000000-0000-0000-0000-0000000000bb")!
        var library = TimetableLibrary.storingCurrent(document, as: "备份", id: backupID)
        library.semester.shortName = "当前"
        let switched = TimetableLibrary.switching(library, to: backupID)
        XCTAssertEqual(switched?.activeTimetableID, backupID)
        XCTAssertEqual(switched?.semester.shortName, document.semester.shortName)
        XCTAssertEqual(switched?.library.map(\.name), ["当前"])
    }

    func testOldStoreStillDecodes() throws {
        let legacy = """
        {"courses":[],"origin":"user","schemaVersion":1,"semester":{"defaultReminderMinutes":10,"name":"学期","periods":[{"end":"08:45","index":1,"start":"08:00"}],"shortName":"秋","startDate":"2026-08-31","totalWeeks":16}}
        """.data(using: .utf8)!
        let outcome = StoreCodec.importing(legacy)
        let document = try XCTUnwrap(outcome.document)
        XCTAssertTrue(document.courses.isEmpty)
        XCTAssertEqual(document.appearance.themeID, "neon")
        XCTAssertEqual(document.activeTimetableID, TimetableLibrary.implicitID)
        XCTAssertTrue(outcome.errors.isEmpty)
    }
}

final class SmartImportTests: XCTestCase {
    func testCSVParsesStandardExport() {
        let csv = """
        课程名称,星期,开始时间,结束时间,教室,教师,周次
        高等数学,周一,08:00,09:40,教学楼A301,陈老师,1-16周
        高等数学,周三,10:10,11:50,教学楼A301,陈老师,1-16周
        大学英语,星期四,08:00,09:40,教学楼B205,林老师,1-16周
        """
        let result = ScheduleTextImporter.parseCSV(csv)
        XCTAssertEqual(result.drafts.count, 2)
        XCTAssertTrue(result.unparsed.isEmpty)
        let math = result.drafts.first { $0.name == "高等数学" }
        XCTAssertEqual(math?.meetings.count, 2)
        XCTAssertEqual(math?.meetings.first?.weekday, 1)
        XCTAssertEqual(math?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(math?.meetings.first?.endMinutes, 580)
        XCTAssertEqual(math?.teacher, "陈老师")
        XCTAssertEqual(math?.firstWeek, 1)
        XCTAssertEqual(math?.lastWeek, 16)
        XCTAssertTrue(math?.issues.isEmpty ?? false)
    }

    func testCSVSemicolonPeriodColumnAndOddWeeks() {
        let csv = """
        课程;星期;节次;地点;周次
        程序设计;周五;5-6;实验楼机房3;1-15周 单周
        """
        let result = ScheduleTextImporter.parseCSV(csv)
        XCTAssertEqual(result.drafts.count, 1)
        let draft = result.drafts.first
        XCTAssertEqual(draft?.meetings.first?.startPeriod, 5)
        XCTAssertEqual(draft?.meetings.first?.endPeriod, 6)
        XCTAssertEqual(draft?.meetings.first?.location, "实验楼机房3")
        XCTAssertEqual(draft?.meetings.first?.parity, 1)
        XCTAssertEqual(draft?.lastWeek, 15)
    }

    func testCSVWithoutHeadersIsReturnedUnparsed() {
        let result = ScheduleTextImporter.parseCSV("a,b,c\n1,2,3")
        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertEqual(result.unparsed.count, 2)
    }

    func testTextLineParsesAllFields() {
        let result = ScheduleTextImporter.parseText("高等数学 周一 08:00-09:40 教学楼A301 陈老师 1-16周")
        XCTAssertEqual(result.drafts.count, 1)
        let draft = result.drafts.first
        XCTAssertEqual(draft?.name, "高等数学")
        XCTAssertEqual(draft?.meetings.first?.weekday, 1)
        XCTAssertEqual(draft?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(draft?.meetings.first?.location, "教学楼A301")
        XCTAssertEqual(draft?.lastWeek, 16)
    }

    func testTextLineWithTwoMeetingsGroupsIntoOneCourse() {
        let text = """
        大学物理 周二 08:00-09:40 周四 10:10-11:50 教学楼A206 赵老师
        这行没有任何课程信息
        """
        let result = ScheduleTextImporter.parseText(text)
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts.first?.meetings.count, 2)
        XCTAssertEqual(result.drafts.first?.meetings.map(\.weekday), [2, 4])
        XCTAssertEqual(result.unparsed, ["这行没有任何课程信息"])
    }

    func testTextMissingLocationFlagsIssueButStaysEditable() {
        let result = ScheduleTextImporter.parseText("体育 周三 14:00-15:40")
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertTrue(result.drafts.first?.issues.contains("教室没认出") ?? false)
    }

    func testHeaderRowIsSkippedNotUnparsed() {
        let result = ScheduleTextImporter.parseText("节次 周一 周二 周三 周四 周五")
        XCTAssertTrue(result.drafts.isEmpty)
        XCTAssertTrue(result.unparsed.isEmpty)
    }
}


final class ChangelogStructureTests: XCTestCase {
    func testChangelogIsNewestFirstAndComplete() {
        let versions = AppChangelog.entries.map(\.version)
        XCTAssertEqual(versions.first, "2.1.0")
        XCTAssertEqual(Set(versions).count, versions.count)
        let parsed = versions.map { $0.split(separator: ".").compactMap { Int($0) } }
        for index in 1..<parsed.count {
            XCTAssertEqual(parsed[index].count, 3)
            let previous = parsed[index - 1], current = parsed[index]
            XCTAssertTrue(
                previous[0] > current[0]
                    || (previous[0] == current[0] && previous[1] > current[1])
                    || (previous[0] == current[0] && previous[1] == current[1] && previous[2] > current[2]),
                "changelog must be newest first")
        }
        for entry in AppChangelog.entries {
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.changes.isEmpty)
            XCTAssertTrue(entry.changes.allSatisfy { !$0.isEmpty })
        }
    }
}
