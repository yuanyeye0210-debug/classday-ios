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
        XCTAssertEqual(mondayState.medium.footerLeft, "课间")
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
        XCTAssertEqual(missing.small.footnote, "打开课间同步，或保留小组件后重装")
        XCTAssertEqual(missing.medium.emptyTitle, "读不到课表")
        XCTAssertTrue(missing.medium.emptyMessage.contains("Sideloadly"))
        XCTAssertTrue(missing.medium.emptyMessage.contains("小组件"))
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
