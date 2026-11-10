import Foundation

public struct WeekSummary: Equatable, Hashable, Sendable {
    public var sessionCount: Int
    public var weekendCount: Int
    public var headline: String
    public var aside: String

    public init(sessionCount: Int, weekendCount: Int, headline: String, aside: String) {
        self.sessionCount = sessionCount
        self.weekendCount = weekendCount
        self.headline = headline
        self.aside = aside
    }
}

public enum ScheduleCopy {
    public static let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    public static func weekdayName(_ weekday: Int) -> String {
        guard weekday >= 1, weekday <= 7 else { return "" }
        return weekdayNames[weekday]
    }

    public static func weekdayShort(_ weekday: Int) -> String {
        guard weekday >= 1, weekday <= 7 else { return "" }
        return String(weekdayNames[weekday].dropFirst())
    }

    public static func periodSpan(_ start: Int, _ end: Int) -> String {
        if start == end { return "第 \(start) 节" }
        return "第 \(start)–\(end) 节"
    }

    public static func timeRange(_ start: ClockTime, _ end: ClockTime) -> String {
        "\(start.hhmm)–\(end.hhmm)"
    }

    public static func weekList(_ weeks: [Int]) -> String {
        let weeks = Array(Set(weeks)).sorted()
        guard let first = weeks.first, let last = weeks.last else { return "未设置周次" }
        if weeks.count == 1 { return "第\(first)周" }
        if weeks == Array(first...last) { return "第\(first)–\(last)周" }
        if weeks.allSatisfy({ $0 % 2 == 1 }),
           weeks == Array(stride(from: 1, through: last, by: 2)) {
            return "单周"
        }
        if weeks.allSatisfy({ $0 % 2 == 0 }),
           weeks == Array(stride(from: first, through: last, by: 2)) {
            return "双周"
        }
        if weeks.count <= 4 {
            return "第" + weeks.map(String.init).joined(separator: "、") + "周"
        }
        return "自定义 \(weeks.count) 周"
    }

    public static func heroTag(kind: String, weeks: [Int]) -> String {
        "\(kind) / \(weekList(weeks))"
    }

    public static func clocks(for meeting: Meeting, semester: Semester) -> (start: ClockTime, end: ClockTime)? {
        let map = periodMap(semester)
        guard let startPeriod = map[meeting.startPeriod], let endPeriod = map[meeting.endPeriod],
              let start = ClockTime.parse(startPeriod.start),
              let end = ClockTime.parse(endPeriod.end) else {
            return nil
        }
        return (start, end)
    }

    public static func heroTime(meeting: Meeting, semester: Semester) -> String {
        guard let clocks = clocks(for: meeting, semester: semester) else {
            return "\(weekdayName(meeting.weekday)) \(periodSpan(meeting.startPeriod, meeting.endPeriod))"
        }
        return "\(weekdayName(meeting.weekday)) \(timeRange(clocks.start, clocks.end))"
    }

    public static func arrangementLines(course: Course, semester: Semester) -> [String] {
        let meetings = course.meetings.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            return $0.startPeriod < $1.startPeriod
        }
        guard let first = meetings.first else { return [semester.name] }
        let sameSpan = meetings.allSatisfy {
            $0.startPeriod == first.startPeriod && $0.endPeriod == first.endPeriod
        }
        var lines: [String] = []
        if sameSpan {
            let pieces = meetings.enumerated().map { index, meeting in
                index == 0
                    ? "每\(weekdayName(meeting.weekday))"
                    : weekdayName(meeting.weekday)
            }
            lines.append("\(periodSpan(first.startPeriod, first.endPeriod)) · \(pieces.joined(separator: "、"))")
        } else {
            for meeting in meetings {
                if let clocks = clocks(for: meeting, semester: semester) {
                    lines.append(
                        "\(weekdayName(meeting.weekday)) · \(periodSpan(meeting.startPeriod, meeting.endPeriod)) · \(timeRange(clocks.start, clocks.end))"
                    )
                } else {
                    lines.append("\(weekdayName(meeting.weekday)) · \(periodSpan(meeting.startPeriod, meeting.endPeriod))")
                }
            }
        }
        lines.append(semester.name)
        return lines
    }

    public static func weekSummary(occurrences: [Occurrence]) -> WeekSummary {
        let weekend = occurrences.filter { $0.weekday >= 6 }.count
        let count = occurrences.count
        let aside: String
        if count == 0 {
            aside = "本周没有课"
        } else if weekend == 0 {
            aside = "周末没有课，好好休息"
        } else {
            aside = "周末有 \(weekend) 门课"
        }
        return WeekSummary(
            sessionCount: count,
            weekendCount: weekend,
            headline: "本周 \(count) 门次",
            aside: aside
        )
    }

    public static func upcomingFootnote(from now: Date, to start: Date, calendar: Calendar) -> String {
        let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
        if minutes < 60 {
            return "距上课 \(minutes) 分钟"
        }
        if calendar.isDate(start, inSameDayAs: now) {
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 { return "距上课 \(hours) 小时" }
            return "距上课 \(hours) 小时 \(remainder) 分钟"
        }
        let startDay = calendar.startOfDay(for: start)
        let nowDay = calendar.startOfDay(for: now)
        let dayGap = calendar.dateComponents([.day], from: nowDay, to: startDay).day ?? 0
        let clock = hhmm(start, calendar: calendar)
        if dayGap == 1 { return "明天 \(clock)" }
        let weekday = weekdayName(SemesterCalendar.isoWeekday(start, calendar: calendar))
        return "\(weekday) \(clock)"
    }

    public static func remainingFootnote(from now: Date, to end: Date) -> String {
        let minutes = max(1, Int(ceil(end.timeIntervalSince(now) / 60.0)))
        return "还剩 \(minutes) 分钟"
    }

    public static func progress(from start: Date, to end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    public static func statusBanner(
        current: Occurrence?,
        next: Occurrence?,
        now: Date,
        calendar: Calendar
    ) -> String? {
        if let current {
            let percent = Int((progress(from: current.start, to: current.end, now: now) * 100).rounded())
            return "正在上课 · \(current.name) · 已上 \(percent)%"
        }
        if let next {
            return "下一节 · \(next.name) · \(upcomingFootnote(from: now, to: next.start, calendar: calendar))"
        }
        return nil
    }

    public static func dayNumber(_ date: Date, calendar: Calendar) -> String {
        String(format: "%02d", calendar.component(.day, from: date))
    }

    public static func monthDayLabel(_ date: Date, calendar: Calendar) -> String {
        let weekday = weekdayName(SemesterCalendar.isoWeekday(date, calendar: calendar))
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(weekday) · \(month)月\(day)日"
    }

    public static func agendaTitle(_ date: Date, calendar: Calendar) -> String {
        let weekday = weekdayName(SemesterCalendar.isoWeekday(date, calendar: calendar))
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日 \(weekday)"
    }

    public static func hhmm(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func conflictMessage(_ conflict: MeetingConflict) -> String {
        let day = weekdayName(conflict.weekday)
        let span = periodSpan(conflict.startPeriod, conflict.endPeriod)
        return "课程「\(conflict.courseName)」与「\(conflict.otherCourseName)」在\(day)\(span)重叠"
    }

    private static func periodMap(_ semester: Semester) -> [Int: PeriodTemplate] {
        var map: [Int: PeriodTemplate] = [:]
        for period in semester.periods {
            map[period.index] = period
        }
        return map
    }
}
