import XCTest
import ClassdayCore

final class V2FeatureTests: XCTestCase {
    private let calendar = TestSupport.calendar()

    func testSevenThemesAndSaverDowngrade() {
        XCTAssertEqual(ClassdayThemes.all.count, 8)
        XCTAssertEqual(Set(ClassdayThemes.all.map(\.id)).count, 8)
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

    func testCSVGridLayout() {
        let csv = """
        节次/时间,周一,周二,周三,周四,周五
        08:00-09:40,高等数学 教学楼A301,,大学英语 教学楼B205,
        10:10-11:50,,程序设计 实验楼机房3,,
        """
        let result = ScheduleTextImporter.parseCSV(csv)
        XCTAssertEqual(Set(result.drafts.map(\.name)), ["高等数学", "大学英语", "程序设计"])
        let math = result.drafts.first { $0.name == "高等数学" }
        XCTAssertEqual(math?.meetings.first?.weekday, 1)
        XCTAssertEqual(math?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(math?.meetings.first?.location, "教学楼A301")
        let english = result.drafts.first { $0.name == "大学英语" }
        XCTAssertEqual(english?.meetings.first?.weekday, 3)
        let coding = result.drafts.first { $0.name == "程序设计" }
        XCTAssertEqual(coding?.meetings.first?.weekday, 2)
        XCTAssertEqual(coding?.meetings.first?.startMinutes, 610)
    }

    func testCSVListWithTitleRowsAndCombinedCell() {
        let csv = """
        2026-2027学年第一学期课表,,
        班级: 软件工程1班,,
        课程名称(代码),授课教师,上课时间,周次
        高等数学(A210331),陈老师,周一 08:00-09:40 教学楼A301,1-16
        ,陈老师,周三 10:10-11:50 教学楼A302,1-16
        大学英语,王老师,周五 14:00-15:40,"1,3,5,7周"
        """
        let result = ScheduleTextImporter.parseCSV(csv)
        let math = result.drafts.first { $0.name == "高等数学" }
        XCTAssertNotNil(math)
        XCTAssertEqual(math?.teacher, "陈老师")
        XCTAssertEqual(math?.meetings.count, 2)
        XCTAssertEqual(math?.meetings.first?.location, "教学楼A301")
        let english = result.drafts.first { $0.name == "大学英语" }
        XCTAssertEqual(english?.customWeeks, [1, 3, 5, 7])
    }

    func testHTMLTableExport() {
        let html = """
        <html><body><table>
        <tr><td>时间</td><td>星期一</td><td>星期二</td><td>星期四</td></tr>
        <tr><td>08:00-09:40</td><td>线性代数 教学楼C101</td><td></td><td>体育 操场</td></tr>
        </table></body></html>
        """
        let result = ScheduleTextImporter.parseHTML(html)
        XCTAssertEqual(Set(result.drafts.map(\.name)), ["线性代数", "体育"])
        XCTAssertEqual(result.drafts.first { $0.name == "体育" }?.meetings.first?.weekday, 4)
    }

    func testXLSXGridFile() {
        let data = Data(base64Encoded: "UEsDBBQAAAAIABIMa11eZo6UIQEAAK4BAAAUAAAAeGwvc2hhcmVkU3RyaW5ncy54bWxtkMFKw0AURfd+xTD7dCatlTYkU1TwC/QDQjI2gWQmZiaiO3FlrSCCBQURClWL2qg7CaI/Y9L0LxwRKaRdPe65990Hz+wchAHYp7HwObOgXsMQUOZw12ddC+5sb2ktCIS0mWsHnFELHlIBO2TFFEICtcqEBT0pIwMh4Xg0tEWNR5QpZ5fHoS2VjLtIRDG1XeFRKsMA1TFeQ6HtMwgcnjBpwTYECfP3Err5r4kpfGJKUp4eF89DE0liol/yR/OL8ff70VLaW0azyyrFLQNjDbeNVVy1Zk9X00mvGLzmk3tQDK7VKO4+1htYX6gePSiz7L+VL5N5cqOOm9Wkjg0da7puNBfOTcf9PDsv088yHYI8vZ09nqmS4iYrTr4a8zBSDyc/UEsDBBQAAAAIABIMa121wty+2AAAANcBAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sbZHdTsMwDEbveYrI98z9gTGhJNPGxBPAA0StWSuapIqjDt6eMKEoq7iLfRx/R4ncf9lJLBR49E5BvalAkOt8P7qzgve31/sdCI7G9WbyjhR8E8Ne38mLD588EEWRFjhWMMQ4PyNyN5A1vPEzuUQ+fLAmpjKckedApr9eshM2VbVFa0YHWl57JxONlsFfREgiqdv9Hg41iKiAU73oSuKiJXZ/7Fiy+pa9lKy5ZaeStZlhys4CTRZoiuGHlUDJHlcCJdv+H9LmkLYYflrZlmy3WoTF02H+E/0DUEsBAhQDFAAAAAgAEgxrXV5mjpQhAQAArgEAABQAAAAAAAAAAAAAAIABAAAAAHhsL3NoYXJlZFN0cmluZ3MueG1sUEsBAhQDFAAAAAgAEgxrXbXC3L7YAAAA1wEAABgAAAAAAAAAAAAAAIABUwEAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAAAgACAIgAAABhAgAAAAA=")!
        let result = ScheduleTextImporter.parseFileData(data)
        XCTAssertNotNil(result)
        XCTAssertEqual(Set(result?.drafts.map(\.name) ?? []), ["高等数学", "大学英语", "程序设计"])
        XCTAssertEqual(result?.drafts.first { $0.name == "程序设计" }?.meetings.first?.weekday, 5)
        XCTAssertEqual(result?.drafts.first { $0.name == "高等数学" }?.meetings.first?.location, "教学楼A301")
    }

    func testDOCXGridFile() {
        let data = Data(base64Encoded: "UEsDBBQAAAAIABIMa12/KAS6FQEAAF4CAAARAAAAd29yZC9kb2N1bWVudC54bWyzsa/IzVEoSy0qzszPs1Uy1DNQUkjNS85PycxLt1UKDXHTtVBSKC5JzEtJzMnPS7VVqkwtVrK347Ipt0rJTy7NTc0rUQCakFdsVW6rlFFSUmClr1+cnJGam1isl1+QmgeUS8svyk0sAXKL0vXL84tSCoryk1OLi4EW5OboGxkYmOnnJmbmKdkBjUzKT6kE0SVJOWCqCEwmg8gCEAHh273oanq2ZqGNPogNIovAZAGYhKjG1PN04oonu3pI1vN09mwy7JmCW48+3Fs4PGdgYWVgoGtgaWViQJrNz3ftf9aw/Mnuxc+mblB4NnXm07XLni3d42xoYEiaOU/2Tn7RtEnh2eTep3N2EfSIPjS29GGxp49IGXYAUEsBAhQDFAAAAAgAEgxrXb8oBLoVAQAAXgIAABEAAAAAAAAAAAAAAIABAAAAAHdvcmQvZG9jdW1lbnQueG1sUEsFBgAAAAABAAEAPwAAAEQBAAAAAA==")!
        let result = ScheduleTextImporter.parseFileData(data)
        XCTAssertNotNil(result)
        XCTAssertEqual(Set(result?.drafts.map(\.name) ?? []), ["线性代数", "体育"])
        XCTAssertEqual(result?.drafts.first { $0.name == "线性代数" }?.meetings.first?.weekday, 2)
    }

    func testEnglishTableLayoutWithSpansAndLegend() {
        let rows: [[String]] = [
            ["MEEC · Full Semester Timetable"],
            ["MEEC-SHU Joint Master Degree"],
            ["Time (时间)", "Monday (周一)", "Tuesday (周二)", "Wednesday (周三)", "Thursday (周四)", "Friday (周五)"],
            ["08:00–08:30", "Image Processing & Vision\nPIVT01 · Room PA1\nWeeks 1–4, 6–7, 9–15", "", "", "", ""],
            ["08:30–09:00", "", "", "", "", ""],
            ["09:00–09:30", "", "", "Analog & Digital Filters\nFAD2T01\nWeeks 2–7: Room AM\nWeeks 9–15: Room FA3", "", ""],
            ["09:30–10:00", "", "", "", "", ""],
            ["10:00–10:30", "", "", "Power Conversion & Storage\nRoom TBA (教室未定)\nEvery 2 weeks (starting Week 2)", "", ""],
            ["Course Legend (课程图例说明)", "", "", "", "", ""],
            ["IPV", "Image Processing and Vision  (图像处理与视觉)", "", "", "", ""],
        ]
        let result = ScheduleTextImporter.parseRows(rows, spans: ["3,1": 6])
        XCTAssertNotNil(result)
        let drafts = result?.drafts ?? []
        XCTAssertEqual(drafts.count, 4)
        let ipv = drafts.first { $0.name == "Image Processing & Vision" }
        XCTAssertEqual(ipv?.meetings.first?.weekday, 1)
        XCTAssertEqual(ipv?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(ipv?.meetings.first?.endMinutes, 600)
        XCTAssertEqual(ipv?.meetings.first?.location, "Room PA1")
        XCTAssertEqual(ipv?.customWeeks, [1, 2, 3, 4, 6, 7, 9, 10, 11, 12, 13, 14, 15])
        let filters = drafts.filter { $0.name == "Analog & Digital Filters" }
        XCTAssertEqual(filters.count, 2)
        XCTAssertEqual(Set(filters.map { $0.meetings.first?.location ?? "" }), ["Room AM", "Room FA3"])
        XCTAssertEqual(Set(filters.map { $0.firstWeek }), [2, 9])
        let power = drafts.first { $0.name == "Power Conversion & Storage" }
        XCTAssertEqual(power?.customWeeks, [2, 4, 6, 8, 10, 12, 14, 16])
        XCTAssertEqual(power?.meetings.first?.location, "")
    }

    func testXLSXMergedCellSpan() {
        let data = Data(base64Encoded: "UEsDBBQAAAAIAGINa130ryk77QAAAFcBAAAUAAAAeGwvc2hhcmVkU3RyaW5ncy54bWxtkMFKAzEQhu8+RZh7m9SFUkuSIoJPoA8QdmN3YTNZd7KiN6+CFw+lSs+KIAUPIiI+jrvStzAiIpS9zPB/P/MdRs7OXcnObE2FRwWjoQBmMfVZgXMFx0eHgwkwCgYzU3q0Ci4swUzvSKLA4imSgjyEaso5pbl1hoa+shibE187E2Ks55yq2pqMcmuDK/muEGPuTIHAUt9gUDAG1mBx2tiDv6wlFVoG3S1fN8sXyYOW/If80vbm8fPtso++X/fQdrXapmIyFWIQZyK2q83T7df6qls8t+sH1i3u4uruP/YTMeqRJFGyF1X/FY+f0d9QSwMEFAAAAAgAYg1rXVfUfGXtAAAA5QEAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxtkd1OAyEQhe99CjL3lv3RxjRAY9v4BPoAhJ3ubsrPBuhW315aK9LGO2a+M2dOBrb+NJrM6MPoLId6UQFBq1w32p7Dx/vb4wuQEKXtpHYWOXxhgLV4YCfnD2FAjCQZ2MBhiHFaURrUgEaGhZvQJrJ33siYSt/TMHmU3WXIaNpU1ZIaOVoQ7NLbySgF8+5EfAqSuur8eK2BRA4h1bOoGJ0Fo+rKNiWrb9m2ZM0t25WszYym3TlAkwM0hfjpLkDJnv83arNRW4iXd0Yt0N85WlzDoO9xi1oHotzRxp/D5C7xuD+nWF3n/+SpyD8kvgFQSwECFAMUAAAACABiDWtd9K8pO+0AAABXAQAAFAAAAAAAAAAAAAAAgAEAAAAAeGwvc2hhcmVkU3RyaW5ncy54bWxQSwECFAMUAAAACABiDWtdV9R8Ze0AAADlAQAAGAAAAAAAAAAAAAAAgAEfAQAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sUEsFBgAAAAACAAIAiAAAAEICAAAAAA==")!
        let result = ScheduleTextImporter.parseFileData(data)
        XCTAssertEqual(result?.drafts.count, 1)
        XCTAssertEqual(result?.drafts.first?.name, "高等数学")
        XCTAssertEqual(result?.drafts.first?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(result?.drafts.first?.meetings.first?.endMinutes, 540)
        XCTAssertEqual(result?.drafts.first?.meetings.first?.location, "教学楼A301")
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

func testGridParsesTimetableScreenshotLayout() {
        func block(_ text: String, _ x: Double, _ y: Double) -> OCRTextBlock {
            OCRTextBlock(text: text, centerX: x, centerY: y, height: 0.02)
        }
        let blocks = [
            block("周一", 0.30, 0.90), block("周三", 0.55, 0.90), block("周五", 0.80, 0.90),
            block("08:00-09:40", 0.08, 0.75),
            block("高等数学 教学楼A301", 0.30, 0.75),
            block("大学英语 教学楼B205", 0.55, 0.75),
            block("10:10-11:50", 0.08, 0.55),
            block("程序设计 实验楼机房3", 0.80, 0.55),
        ]
        let result = ScheduleTextImporter.parseGrid(blocks)
        XCTAssertEqual(result?.drafts.count, 3)
        let math = result?.drafts.first { $0.name == "高等数学" }
        XCTAssertEqual(math?.meetings.first?.weekday, 1)
        XCTAssertEqual(math?.meetings.first?.startMinutes, 480)
        XCTAssertEqual(math?.meetings.first?.endMinutes, 580)
        XCTAssertEqual(math?.meetings.first?.location, "教学楼A301")
        let cs = result?.drafts.first { $0.name == "程序设计" }
        XCTAssertEqual(cs?.meetings.first?.weekday, 5)
        XCTAssertEqual(cs?.meetings.first?.startMinutes, 610)
    }

    func testGridReturnsNilForNonGridText() {
        let blocks = [OCRTextBlock(text: "高等数学", centerX: 0.5, centerY: 0.5, height: 0.02)]
        XCTAssertNil(ScheduleTextImporter.parseGrid(blocks))
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
        XCTAssertEqual(versions.first, "2.3.1")
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
