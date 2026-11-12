import Foundation

public enum SemesterCalendar {
    public static func parseCivil(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
            return nil
        }
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }
        guard calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return nil
        }
        return date
    }

    public static func formatCivil(_ date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Monday = 1 ... Sunday = 7.
    public static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    public static func monday(onOrBefore date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let iso = isoWeekday(day, calendar: calendar)
        return calendar.date(byAdding: .day, value: -(iso - 1), to: day) ?? day
    }

    public static func semesterMonday(_ semester: Semester, calendar: Calendar) -> Date? {
        guard let start = parseCivil(semester.startDate, calendar: calendar) else { return nil }
        return monday(onOrBefore: start, calendar: calendar)
    }

    public static func weekIndex(for date: Date, semester: Semester, calendar: Calendar) -> Int? {
        guard let startMonday = semesterMonday(semester, calendar: calendar) else { return nil }
        let thisMonday = monday(onOrBefore: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: startMonday, to: thisMonday).day ?? 0
        guard days >= 0 else { return nil }
        let week = days / 7 + 1
        guard week >= 1, week <= semester.totalWeeks else { return nil }
        return week
    }

    public static func dates(inWeek week: Int, semester: Semester, calendar: Calendar) -> [Date] {
        guard week >= 1, week <= semester.totalWeeks, let startMonday = semesterMonday(semester, calendar: calendar) else { return [] }
        guard let monday = calendar.date(byAdding: .day, value: (week - 1) * 7, to: startMonday) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    public static func date(
        week: Int,
        weekday: Int,
        time: ClockTime,
        semester: Semester,
        calendar: Calendar
    ) -> Date? {
        let days = dates(inWeek: week, semester: semester, calendar: calendar)
        guard weekday >= 1, weekday <= days.count else { return nil }
        let day = days[weekday - 1]
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        components.timeZone = calendar.timeZone
        components.calendar = calendar
        return calendar.date(from: components)
    }

    public static func weekRangeLabel(week: Int, semester: Semester, calendar: Calendar) -> String {
        let days = dates(inWeek: week, semester: semester, calendar: calendar)
        guard let first = days.first, let last = days.last else { return "" }
        let startMonth = calendar.component(.month, from: first)
        let startDay = calendar.component(.day, from: first)
        let endMonth = calendar.component(.month, from: last)
        let endDay = calendar.component(.day, from: last)
        return String(format: "%02d.%02d – %02d.%02d", startMonth, startDay, endMonth, endDay)
    }

    public static func contains(_ date: Date, semester: Semester, calendar: Calendar) -> Bool {
        weekIndex(for: date, semester: semester, calendar: calendar) != nil
    }

    /// The holiday / no-class period covering a date, if any (civil-string compare).
    public static func holiday(on date: Date, semester: Semester, calendar: Calendar) -> HolidayPeriod? {
        let civil = formatCivil(date, calendar: calendar)
        return semester.holidays.first { $0.startDate <= civil && civil <= $0.endDate }
    }


    /// The class cancellation covering a specific session start, if any.
    /// A whole-day cancellation (courseID nil, scope "day") matches every
    /// course; otherwise the course must match and the scope selects all of
    /// that course's sessions that day, the morning ones ("am", starting
    /// before 12:00) or the afternoon ones ("pm").
    public static func cancellation(on date: Date, courseID: UUID, semester: Semester, calendar: Calendar) -> ClassCancellation? {
        let civil = formatCivil(date, calendar: calendar)
        let hour = calendar.component(.hour, from: date)
        return semester.cancellations.first { entry in
            guard entry.date == civil else { return false }
            if let entryCourse = entry.courseID, entryCourse != courseID { return false }
            switch entry.scope {
            case "day", "all": return true
            case "am": return hour < 12
            case "pm": return hour >= 12
            default: return true
            }
        }
    }

    /// The semester's last day: the Sunday of its final week.
    public static func endDate(semester: Semester, calendar: Calendar) -> Date? {
        guard let monday = semesterMonday(semester, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: semester.totalWeeks * 7 - 1, to: monday)
    }
}
