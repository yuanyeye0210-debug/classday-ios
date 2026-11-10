import XCTest
import ClassdayCore

final class V2FeatureTests: XCTestCase {
    private let calendar = TestSupport.calendar()

    func testICloudEntitlementIsAbsentUnlessTheProfileGrantsIt() {
        XCTAssertFalse(SignedEntitlements.allowsICloud(Data("not a profile".utf8)))
        let plain = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Entitlements</key><dict>
        <key>com.apple.security.application-groups</key>
        <array><string>group.com.classday.shared</string></array>
        </dict></dict></plist>
        """
        XCTAssertFalse(SignedEntitlements.allowsICloud(Data(plain.utf8)))
        let granted = plain.replacingOccurrences(
            of: "</dict></dict></plist>",
            with: "<key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array></dict></dict></plist>"
        )
        XCTAssertTrue(SignedEntitlements.allowsICloud(Data(granted.utf8)))
    }

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
