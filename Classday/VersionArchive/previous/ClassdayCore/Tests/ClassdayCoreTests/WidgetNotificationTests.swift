import XCTest
import ClassdayCore

final class WidgetNotificationTests: XCTestCase {
    private let calendar = TestSupport.calendar()
    private let document = DemoData.makeDocument()

    func testSmallAndMediumWidgetsFollowLocalDate() {
        let mondayMorning = TestSupport.date(2026, 11, 2, 7, 40, calendar: calendar)
        let mondayState = WidgetProjection.state(at: mondayMorning, document: document, calendar: calendar)
        XCTAssertEqual(mondayState.small.phase, .upcoming)
        XCTAssertEqual(mondayState.small.badge, "待上课")
        XCTAssertEqual(mondayState.small.name, "高等数学")
        XCTAssertEqual(mondayState.small.timeText, "08:00")
        XCTAssertEqual(mondayState.small.locationText, "教学楼 A · 301")
        XCTAssertEqual(mondayState.small.footnote, "距上课 20 分钟")
        XCTAssertEqual(mondayState.small.url.flatMap(ClassdayLink.parse)?.courseID, DemoData.ID.calculus)

        XCTAssertFalse(mondayState.medium.isEmpty)
        XCTAssertEqual(mondayState.medium.dateText, "周一 · 11月2日")
        XCTAssertEqual(mondayState.medium.chips.map(\.name), ["高等数学", "大学英语", "程序设计"])
        XCTAssertEqual(mondayState.medium.chips.map(\.timeText), ["08:00", "10:10", "14:00"])
        XCTAssertEqual(mondayState.medium.chips.map(\.locationText), ["A · 301", "B · 205", "机房 2"])
        XCTAssertEqual(mondayState.medium.footerLeft, "课曜")
        XCTAssertEqual(mondayState.medium.footerRight, "今天共 3 门课")

        let sunday = TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar)
        let sundayState = WidgetProjection.state(at: sunday, document: document, calendar: calendar)
        XCTAssertTrue(sundayState.medium.isEmpty)
        XCTAssertEqual(sundayState.medium.emptyTitle, "今天没有课")
        XCTAssertEqual(sundayState.medium.footerRight, "今天没有课")
        XCTAssertEqual(sundayState.small.name, "高等数学")
        XCTAssertEqual(sundayState.small.footnote, "明天 08:00")

        let during = TestSupport.date(2026, 11, 9, 8, 30, calendar: calendar)
        let live = WidgetProjection.state(at: during, document: document, calendar: calendar)
        XCTAssertEqual(live.small.phase, .inProgress)
        XCTAssertEqual(live.small.badge, "上课中")
        XCTAssertEqual(live.small.footnote, "还剩 70 分钟")
        XCTAssertEqual(live.small.progress ?? -1, 0.3, accuracy: 0.001)
    }

    func testMediumWidgetKeepsThreeRelevantChips() {
        var crowded = DemoData.makeDocument()
        let names = ["一", "二", "三", "四"]
        let slots = [(1, 1), (3, 3), (5, 5), (7, 7)]
        crowded.courses = zip(names, slots).enumerated().map { index, pair in
            Course(
                id: UUID(uuidString: "30000000-0000-0000-0000-00000000000\(index + 1)")!,
                name: pair.0,
                teacher: "教师",
                location: "教室",
                colorID: "blue",
                weeks: Array(1...16),
                meetings: [
                    Meeting(
                        id: UUID(uuidString: "40000000-0000-0000-0000-00000000000\(index + 1)")!,
                        weekday: 1,
                        startPeriod: pair.1.0,
                        endPeriod: pair.1.1
                    ),
                ]
            )
        }
        let early = TestSupport.date(2026, 11, 2, 7, 0, calendar: calendar)
        let earlyNames = WidgetProjection.state(at: early, document: crowded, calendar: calendar).medium.chips.map(\.name)
        XCTAssertEqual(earlyNames, ["一", "二", "三"])
        XCTAssertEqual(
            WidgetProjection.state(at: early, document: crowded, calendar: calendar).medium.footerRight,
            "今天共 4 门课"
        )
        let noon = TestSupport.date(2026, 11, 2, 12, 0, calendar: calendar)
        let noonNames = WidgetProjection.state(at: noon, document: crowded, calendar: calendar).medium.chips.map(\.name)
        XCTAssertEqual(noonNames, ["二", "三", "四"])
    }

    func testTimelineUsesClassBoundariesNotMinutePolling() {
        let now = TestSupport.date(2026, 11, 9, 7, 40, calendar: calendar)
        let plan = WidgetProjection.timelinePlan(now: now, document: document, calendar: calendar)
        XCTAssertEqual(plan.entryDates.first, now)
        XCTAssertLessThanOrEqual(plan.entryDates.count, WidgetProjection.maximumEntries)
        XCTAssertGreaterThan(plan.entryDates.count, 3)
        XCTAssertEqual(plan.refreshAfter, plan.entryDates.last)
        var previous = plan.entryDates[0]
        for date in plan.entryDates.dropFirst() {
            XCTAssertGreaterThanOrEqual(date.timeIntervalSince(previous), 15 * 60)
            previous = date
        }
        let eight = TestSupport.date(2026, 11, 9, 8, 0, calendar: calendar)
        XCTAssertTrue(plan.entryDates.contains(eight))

        var empty = document
        empty.courses = []
        let quiet = WidgetProjection.timelinePlan(now: now, document: empty, calendar: calendar)
        XCTAssertGreaterThanOrEqual(quiet.refreshAfter.timeIntervalSince(now), WidgetProjection.minimumRefreshInterval)
        let missing = WidgetProjection.missingStoreState(at: now, calendar: calendar)
        XCTAssertEqual(missing.small.phase, .empty)
        XCTAssertEqual(missing.small.name, "读不到课表")
        XCTAssertEqual(missing.small.footnote, "打开课曜同步，或保留小组件后重装")
        XCTAssertEqual(missing.medium.emptyTitle, "读不到课表")
        XCTAssertTrue(missing.medium.emptyMessage.contains("Sideloadly"))
        XCTAssertTrue(missing.medium.emptyMessage.contains("小组件"))
    }

    func testTimelinePlanSevenDayHorizonReachesNextMondayFirstClass() {
        // Friday 16:00: the last class (程序设计 14:00–15:40) has ended.
        // Under the old 36h horizon the plan stopped at Sunday 04:00 and
        // Monday's first class was invisible; with the 7-day horizon the
        // entries must reach Monday 08:00 高等数学.
        let now = TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar)
        let plan = WidgetProjection.timelinePlan(now: now, document: document, calendar: calendar)
        XCTAssertEqual(WidgetProjection.horizon, 7 * 24 * 60 * 60)
        XCTAssertEqual(plan.entryDates.first, now)
        XCTAssertEqual(plan.entryDates, plan.entryDates.sorted())
        XCTAssertLessThanOrEqual(plan.entryDates.count, WidgetProjection.maximumEntries)
        XCTAssertTrue(plan.entryDates.contains(TestSupport.date(2026, 11, 16, 0, 0, calendar: calendar)))
        XCTAssertTrue(plan.entryDates.contains(TestSupport.date(2026, 11, 16, 8, 0, calendar: calendar)))
        // now + 7 midnights (Nov 14–20) + 10 class starts + 10 class ends.
        XCTAssertEqual(plan.entryDates.count, 28)
        // refreshAfter is unchanged semantics: the last entry, Friday's
        // last class end (程序设计 15:40).
        XCTAssertEqual(plan.refreshAfter, plan.entryDates.last)
        XCTAssertEqual(plan.refreshAfter, TestSupport.date(2026, 11, 20, 15, 40, calendar: calendar))
    }

    func testTimelinePlanCapsEntriesAndDropsClassEndsFirst() {
        // Five classes a day, Monday–Friday: 25 starts + 25 ends + 7
        // midnights = 57 boundaries in 7 days, over the 40-entry cap.
        // D6: midnights and class starts are kept first; class ends are
        // dropped, earliest ends first.
        var crowded = DemoData.makeDocument()
        let slots = [(1, 1), (3, 3), (5, 5), (7, 7), (9, 9)]
        crowded.courses = slots.enumerated().map { index, slot in
            Course(
                id: UUID(),
                name: "课\(index + 1)",
                teacher: "教师",
                location: "教室",
                colorID: "blue",
                weeks: Array(1...16),
                meetings: (1...5).map { weekday in
                    Meeting(id: UUID(), weekday: weekday, startPeriod: slot.0, endPeriod: slot.1)
                }
            )
        }
        let now = TestSupport.date(2026, 11, 13, 16, 0, calendar: calendar)
        let plan = WidgetProjection.timelinePlan(now: now, document: crowded, calendar: calendar)
        XCTAssertEqual(plan.entryDates.count, WidgetProjection.maximumEntries)
        XCTAssertEqual(plan.entryDates, plan.entryDates.sorted())
        for day in 14...20 {
            XCTAssertTrue(
                plan.entryDates.contains(TestSupport.date(2026, 11, day, 0, 0, calendar: calendar)),
                "midnight Nov \(day) must be kept"
            )
        }
        // The latest class start in the horizon (Friday Nov 20 14:00)
        // must survive the cap — a plain chronological truncation would
        // have cut everything after Wednesday evening instead.
        XCTAssertTrue(plan.entryDates.contains(TestSupport.date(2026, 11, 20, 14, 0, calendar: calendar)))
        // Only the 7 earliest ends fit after the 32 priority entries:
        // Fri 16:55, Fri 19:45, Mon 08:45, 10:55, 14:45, 16:55, 19:45.
        XCTAssertTrue(plan.entryDates.contains(TestSupport.date(2026, 11, 16, 19, 45, calendar: calendar)))
        XCTAssertFalse(plan.entryDates.contains(TestSupport.date(2026, 11, 17, 8, 45, calendar: calendar)))
        XCTAssertFalse(plan.entryDates.contains(TestSupport.date(2026, 11, 20, 14, 45, calendar: calendar)))
        // refreshAfter is unchanged semantics: the last entry.
        XCTAssertEqual(plan.refreshAfter, plan.entryDates.last)
        XCTAssertEqual(plan.refreshAfter, TestSupport.date(2026, 11, 20, 14, 0, calendar: calendar))
    }

    func testNotificationPlanLeadTimeOrderAndCap() {
        let sunday = TestSupport.date(2026, 11, 8, 12, 0, calendar: calendar)
        let planned = NotificationPlan.make(document: document, now: sunday, calendar: calendar)
        XCTAssertFalse(planned.isEmpty)
        XCTAssertLessThanOrEqual(planned.count, NotificationPlan.pendingLimit)
        XCTAssertEqual(planned, planned.sorted { $0.fireDate < $1.fireDate })
        XCTAssertEqual(planned[0].title, "即将上课 · 高等数学")
        XCTAssertEqual(planned[0].fireDate, TestSupport.date(2026, 11, 9, 7, 50, calendar: calendar))
        XCTAssertTrue(planned[0].body.contains("10 分钟后"))
        XCTAssertTrue(planned[0].body.contains("教学楼 A · 301"))
        XCTAssertTrue(planned.contains { $0.courseID == DemoData.ID.english && $0.fireDate == TestSupport.date(2026, 11, 9, 10, 0, calendar: calendar) })

        let duringLead = TestSupport.date(2026, 11, 9, 7, 55, calendar: calendar)
        let later = NotificationPlan.make(document: document, now: duringLead, calendar: calendar)
        XCTAssertFalse(later.contains { $0.courseID == DemoData.ID.calculus && $0.fireDate < duringLead })
        XCTAssertEqual(later.first?.courseID, DemoData.ID.english)

        var muted = document
        muted.courses[0].reminderLeadMinutes = 0
        let mutedPlan = NotificationPlan.make(document: muted, now: sunday, calendar: calendar)
        XCTAssertFalse(mutedPlan.contains { $0.courseID == DemoData.ID.calculus })

        let capped = NotificationPlan.make(document: document, now: sunday, calendar: calendar, limit: 2)
        XCTAssertEqual(capped.count, 2)
        XCTAssertLessThan(capped[0].fireDate, capped[1].fireDate)
    }
}
