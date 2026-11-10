import Foundation

public struct WidgetChip: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var timeText: String
    public var name: String
    public var locationText: String
    public var colorID: String
    public var url: URL

    public init(id: String, timeText: String, name: String, locationText: String, colorID: String, url: URL) {
        self.id = id
        self.timeText = timeText
        self.name = name
        self.locationText = locationText
        self.colorID = colorID
        self.url = url
    }
}

public struct SmallWidgetState: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case inProgress
        case upcoming
        case empty
    }

    public var phase: Phase
    public var badge: String
    public var timeText: String
    public var name: String
    public var locationText: String
    public var footnote: String
    public var colorID: String
    public var progress: Double?
    public var url: URL?

    public init(
        phase: Phase,
        badge: String,
        timeText: String,
        name: String,
        locationText: String,
        footnote: String,
        colorID: String,
        progress: Double?,
        url: URL?
    ) {
        self.phase = phase
        self.badge = badge
        self.timeText = timeText
        self.name = name
        self.locationText = locationText
        self.footnote = footnote
        self.colorID = colorID
        self.progress = progress
        self.url = url
    }
}

public struct MediumWidgetState: Equatable, Sendable {
    public var title: String
    public var dateText: String
    public var chips: [WidgetChip]
    public var footerLeft: String
    public var footerRight: String
    public var isEmpty: Bool
    public var emptyTitle: String
    public var emptyMessage: String

    public init(
        title: String,
        dateText: String,
        chips: [WidgetChip],
        footerLeft: String,
        footerRight: String,
        isEmpty: Bool,
        emptyTitle: String,
        emptyMessage: String
    ) {
        self.title = title
        self.dateText = dateText
        self.chips = chips
        self.footerLeft = footerLeft
        self.footerRight = footerRight
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
    }
}

public struct WidgetRenderState: Equatable, Sendable {
    public var small: SmallWidgetState
    public var medium: MediumWidgetState

    public init(small: SmallWidgetState, medium: MediumWidgetState) {
        self.small = small
        self.medium = medium
    }
}

public struct TimelinePlan: Equatable, Sendable {
    public var entryDates: [Date]
    public var refreshAfter: Date

    public init(entryDates: [Date], refreshAfter: Date) {
        self.entryDates = entryDates
        self.refreshAfter = refreshAfter
    }
}

public enum WidgetProjection {
    /// WidgetKit budgets reloads. Timelines carry the boundaries, so the app reloads only after edits.
    public static let minimumRefreshInterval: TimeInterval = 15 * 60
    public static let horizon: TimeInterval = 36 * 60 * 60
    public static let maximumEntries = 40
    public static let visibleChipLimit = 3

    public static func state(at date: Date, document: StoreDocument, calendar: Calendar) -> WidgetRenderState {
        let current = ScheduleEngine.currentOccurrence(
            at: date,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        let next = ScheduleEngine.nextOccurrence(
            after: date,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        return WidgetRenderState(
            small: smallState(current: current, next: next, now: date, document: document, calendar: calendar),
            medium: mediumState(at: date, document: document, calendar: calendar)
        )
    }

    public static func missingStoreState(at date: Date, calendar: Calendar) -> WidgetRenderState {
        let small = SmallWidgetState(
            phase: .empty,
            badge: "未同步",
            timeText: "—",
            name: "打开课间",
            locationText: "",
            footnote: "同步后显示下一节课",
            colorID: "blue",
            progress: nil,
            url: nil
        )
        let medium = MediumWidgetState(
            title: "今日课程",
            dateText: ScheduleCopy.monthDayLabel(date, calendar: calendar),
            chips: [],
            footerLeft: "课间",
            footerRight: "尚未同步",
            isEmpty: true,
            emptyTitle: "还没有课表",
            emptyMessage: "打开课间后会显示在这里"
        )
        return WidgetRenderState(small: small, medium: medium)
    }

    public static func timelinePlan(now: Date, document: StoreDocument, calendar: Calendar) -> TimelinePlan {
        let horizonEnd = now.addingTimeInterval(horizon)
        var boundaries: [Date] = []
        var day = calendar.startOfDay(for: now)
        while day <= horizonEnd {
            if day > now { boundaries.append(day) }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        if let scan = scanWeeks(from: now, through: horizonEnd, semester: document.semester, calendar: calendar) {
            for week in scan {
                let items = ScheduleEngine.occurrences(
                    inWeek: week,
                    courses: document.courses,
                    semester: document.semester,
                    calendar: calendar
                )
                for item in items {
                    if item.start > now && item.start <= horizonEnd { boundaries.append(item.start) }
                    if item.end > now && item.end <= horizonEnd { boundaries.append(item.end) }
                }
            }
        }

        var dates = [now]
        for boundary in boundaries.sorted() {
            guard boundary > now else { continue }
            if let last = dates.last, boundary.timeIntervalSince(last) < 1 { continue }
            dates.append(boundary)
            if dates.count == maximumEntries { break }
        }

        let refreshAfter: Date
        if dates.count >= 2, let last = dates.last {
            refreshAfter = last
        } else {
            refreshAfter = now.addingTimeInterval(max(minimumRefreshInterval, 6 * 60 * 60))
        }
        return TimelinePlan(entryDates: dates, refreshAfter: refreshAfter)
    }

    private static func smallState(
        current: Occurrence?,
        next: Occurrence?,
        now: Date,
        document: StoreDocument,
        calendar: Calendar
    ) -> SmallWidgetState {
        if let current {
            return SmallWidgetState(
                phase: .inProgress,
                badge: "上课中",
                timeText: ScheduleCopy.hhmm(current.start, calendar: calendar),
                name: current.name,
                locationText: current.location,
                footnote: ScheduleCopy.remainingFootnote(from: now, to: current.end),
                colorID: current.colorID,
                progress: ScheduleCopy.progress(from: current.start, to: current.end, now: now),
                url: ClassdayLink.course(current.courseID, meeting: current.meetingID)
            )
        }
        if let next {
            return SmallWidgetState(
                phase: .upcoming,
                badge: "待上课",
                timeText: ScheduleCopy.hhmm(next.start, calendar: calendar),
                name: next.name,
                locationText: next.location,
                footnote: ScheduleCopy.upcomingFootnote(from: now, to: next.start, calendar: calendar),
                colorID: next.colorID,
                progress: nil,
                url: ClassdayLink.course(next.courseID, meeting: next.meetingID)
            )
        }
        if document.courses.isEmpty {
            return SmallWidgetState(
                phase: .empty,
                badge: "无课程",
                timeText: "—",
                name: "还没有课程",
                locationText: "",
                footnote: "打开课间添加一门课",
                colorID: "blue",
                progress: nil,
                url: nil
            )
        }
        return SmallWidgetState(
            phase: .empty,
            badge: "无课程",
            timeText: "—",
            name: "没有更多课",
            locationText: "",
            footnote: "本学期没有更多课程",
            colorID: "blue",
            progress: nil,
            url: nil
        )
    }

    private static func mediumState(at date: Date, document: StoreDocument, calendar: Calendar) -> MediumWidgetState {
        let dateText = ScheduleCopy.monthDayLabel(date, calendar: calendar)
        let today = ScheduleEngine.occurrences(
            on: date,
            courses: document.courses,
            semester: document.semester,
            calendar: calendar
        )
        if today.isEmpty {
            return MediumWidgetState(
                title: "今日课程",
                dateText: dateText,
                chips: [],
                footerLeft: "课间",
                footerRight: "今天没有课",
                isEmpty: true,
                emptyTitle: "今天没有课",
                emptyMessage: "好好休息"
            )
        }
        let visible = chipsToShow(today, at: date)
        let chips = visible.map { item in
            WidgetChip(
                id: item.id,
                timeText: ScheduleCopy.hhmm(item.start, calendar: calendar),
                name: item.name,
                locationText: item.locationShort,
                colorID: item.colorID,
                url: ClassdayLink.course(item.courseID, meeting: item.meetingID)
            )
        }
        return MediumWidgetState(
            title: "今日课程",
            dateText: dateText,
            chips: chips,
            footerLeft: "课间",
            footerRight: "今天共 \(today.count) 门课",
            isEmpty: false,
            emptyTitle: "",
            emptyMessage: ""
        )
    }

    static func chipsToShow(_ today: [Occurrence], at date: Date) -> [Occurrence] {
        let sorted = today.sorted { $0.start < $1.start }
        guard sorted.count > visibleChipLimit else { return sorted }
        let pending = sorted.filter { $0.end > date }
        if pending.count >= visibleChipLimit {
            return Array(pending.prefix(visibleChipLimit))
        }
        return Array(sorted.suffix(visibleChipLimit))
    }

    private static func scanWeeks(
        from start: Date,
        through end: Date,
        semester: Semester,
        calendar: Calendar
    ) -> ClosedRange<Int>? {
        guard let semesterMonday = SemesterCalendar.semesterMonday(semester, calendar: calendar) else {
            return nil
        }
        let first: Int
        if start < semesterMonday {
            first = 1
        } else if let week = SemesterCalendar.weekIndex(for: start, semester: semester, calendar: calendar) {
            first = week
        } else {
            return nil
        }
        let last: Int
        if end < semesterMonday {
            return nil
        } else if let week = SemesterCalendar.weekIndex(for: end, semester: semester, calendar: calendar) {
            last = week
        } else if start < semesterMonday {
            last = 1
        } else {
            last = semester.totalWeeks
        }
        guard first <= last else { return nil }
        return first...min(last, semester.totalWeeks)
    }
}
