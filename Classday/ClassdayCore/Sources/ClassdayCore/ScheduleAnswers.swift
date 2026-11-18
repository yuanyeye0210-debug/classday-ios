import Foundation

/// Read-only answers shared by Siri and shortcuts. Missing data never becomes demo data.
public enum ScheduleAnswers {
    public static func classroom(document: StoreDocument?, at date: Date, calendar: Calendar) -> String {
        guard let document else { return "读不到课表，请先打开课曜同步后再试。" }
        guard let course = TodayProjection.make(at: date, document: document, calendar: calendar).classroomCourse else {
            return "现在没有正在上的课程，课曜会在上课时自动进入应用内专注。不会开启系统专注模式。"
        }
        return "正在上\(course.name)，已打开课曜的应用内上课专注。不会开启系统专注模式。"
    }

    public static func nextClass(document: StoreDocument?, at date: Date, calendar: Calendar) -> String {
        guard let document else { return "读不到课表，请先打开课曜同步后再试。" }
        guard let next = ScheduleEngine.nextOccurrence(after: date, courses: document.courses,
            semester: document.semester, calendar: calendar, context: document.scheduleContext) else {
            return "本学期没有待上的课程。"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        let room = next.location.isEmpty ? "" : "，地点是\(next.location)"
        return "下节课是\(next.name)，\(formatter.string(from: next.start))开始\(room)。"
    }

    public static func endOfDay(document: StoreDocument?, at date: Date, calendar: Calendar) -> String {
        guard let document else { return "读不到课表，请先打开课曜同步后再试。" }
        let today = ScheduleEngine.occurrences(on: date, courses: document.courses,
            semester: document.semester, calendar: calendar, context: document.scheduleContext)
        guard let end = today.map({ $0.end }).max() else { return "今天没有课程。" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: end)
        return date >= end ? "今天的课程已在\(time)结束。" : "今天\(time)下课。"
    }
}
