import Foundation

public enum DemoData {
    public enum ID {
        public static let calculus = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        public static let english = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        public static let programming = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        public static let physics = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        public static let linear = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        public static let pe = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!

        public static let calculusMonday = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        public static let calculusWednesday = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        public static let englishMonday = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        public static let englishThursday = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        public static let programmingMonday = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!
        public static let programmingFriday = UUID(uuidString: "20000000-0000-0000-0000-000000000006")!
        public static let physicsTuesday = UUID(uuidString: "20000000-0000-0000-0000-000000000007")!
        public static let physicsThursday = UUID(uuidString: "20000000-0000-0000-0000-000000000008")!
        public static let linearTuesday = UUID(uuidString: "20000000-0000-0000-0000-000000000009")!
        public static let peTuesday = UUID(uuidString: "20000000-0000-0000-0000-00000000000A")!
        public static let examCalculus = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        public static let examPhysics = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        public static let examEnglish = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        public static let examProgramming = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!
        public static let homeworkCalculus = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        public static let homeworkProgramming = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        public static let eventGym = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        public static let eventLab = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
    }

    public static func makeDocument() -> StoreDocument {
        StoreDocument(
            schemaVersion: StoreDocument.currentSchema,
            origin: .demo,
            semester: makeSemester(),
            courses: makeCourses(),
            exams: [
                ExamEvent(id: ID.examCalculus, courseName: "高等数学", location: "教学楼 A · 301", startISO: "2026-12-22T09:00", endISO: "2026-12-22T11:00", note: "期末考试"),
                ExamEvent(id: ID.examPhysics, courseName: "大学物理", location: "教学楼 A · 206", startISO: "2026-12-24T14:00", endISO: "2026-12-24T16:00", note: "期末考试"),
                ExamEvent(id: ID.examEnglish, courseName: "大学英语", location: "教学楼 B · 205", startISO: "2026-12-29T10:10", endISO: "2026-12-29T12:10", note: "期末考试"),
                ExamEvent(id: ID.examProgramming, courseName: "程序设计", location: "机房 2", startISO: "2027-01-05T14:00", endISO: "2027-01-05T16:00", note: "期末考试")
            ],
            homework: [
                HomeworkTask(id: ID.homeworkCalculus, courseName: "高等数学", title: "第三章习题", dueISO: "2026-11-11T23:59"),
                HomeworkTask(id: ID.homeworkProgramming, courseName: "程序设计", title: "实验报告", dueISO: "2026-11-13T23:59")
            ],
            personalEvents: [
                PersonalEvent(id: ID.eventGym, title: "健身", note: "VivaGym · 练背 + 有氧", startISO: "2026-11-10T18:30", endISO: "2026-11-10T20:00"),
                PersonalEvent(id: ID.eventLab, title: "实验室组会", note: "Lab 2 小组 · 讨论报告", startISO: "2026-11-10T20:30", endISO: "2026-11-10T21:30")
            ]
        )
    }

    public static func makeSemester() -> Semester {
        Semester(
            name: "2026-2027 学年 · 第一学期",
            shortName: "2026 秋季学期",
            startDate: "2026-08-31",
            totalWeeks: 16,
            periods: [
                PeriodTemplate(index: 1, start: "08:00", end: "08:45"),
                PeriodTemplate(index: 2, start: "08:55", end: "09:40"),
                PeriodTemplate(index: 3, start: "10:10", end: "10:55"),
                PeriodTemplate(index: 4, start: "11:05", end: "11:50"),
                PeriodTemplate(index: 5, start: "14:00", end: "14:45"),
                PeriodTemplate(index: 6, start: "14:55", end: "15:40"),
                PeriodTemplate(index: 7, start: "16:10", end: "16:55"),
                PeriodTemplate(index: 8, start: "17:05", end: "17:50"),
                PeriodTemplate(index: 9, start: "19:00", end: "19:45"),
                PeriodTemplate(index: 10, start: "19:55", end: "20:40"),
            ],
            defaultReminderMinutes: 10
        )
    }

    public static func makeCourses() -> [Course] {
        let weeks = Array(1...16)
        return [
            Course(
                id: ID.calculus,
                name: "高等数学",
                teacher: "陈老师",
                location: "教学楼 A · 301",
                department: "数学与统计学院",
                note: "请提前 5 分钟到达教室",
                colorID: "blue",
                kind: "必修课",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.calculusMonday, weekday: 1, startPeriod: 1, endPeriod: 2),
                    Meeting(id: ID.calculusWednesday, weekday: 3, startPeriod: 3, endPeriod: 4),
                ],
                reminderLeadMinutes: 10
            ),
            Course(
                id: ID.english,
                name: "大学英语",
                teacher: "林老师",
                location: "教学楼 B · 205",
                department: "外国语学院",
                colorID: "green",
                kind: "必修课",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.englishMonday, weekday: 1, startPeriod: 3, endPeriod: 4),
                    Meeting(id: ID.englishThursday, weekday: 4, startPeriod: 1, endPeriod: 2),
                ]
            ),
            Course(
                id: ID.programming,
                name: "程序设计",
                teacher: "周老师",
                location: "机房 2",
                department: "计算机学院",
                colorID: "purple",
                kind: "必修课",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.programmingMonday, weekday: 1, startPeriod: 5, endPeriod: 6),
                    Meeting(id: ID.programmingFriday, weekday: 5, startPeriod: 5, endPeriod: 6),
                ]
            ),
            Course(
                id: ID.physics,
                name: "大学物理",
                teacher: "赵老师",
                location: "教学楼 A · 206",
                department: "物理学院",
                colorID: "orange",
                kind: "必修课",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.physicsTuesday, weekday: 2, startPeriod: 1, endPeriod: 2),
                    Meeting(id: ID.physicsThursday, weekday: 4, startPeriod: 3, endPeriod: 4),
                ]
            ),
            Course(
                id: ID.linear,
                name: "线性代数",
                teacher: "吴老师",
                location: "教学楼 A · 302",
                department: "数学与统计学院",
                colorID: "pink",
                kind: "必修课",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.linearTuesday, weekday: 2, startPeriod: 5, endPeriod: 6),
                ]
            ),
            Course(
                id: ID.pe,
                name: "大学体育",
                teacher: "孙老师",
                location: "体育馆",
                department: "体育部",
                colorID: "sage",
                kind: "实践",
                weeks: weeks,
                meetings: [
                    Meeting(id: ID.peTuesday, weekday: 2, startPeriod: 7, endPeriod: 8),
                ]
            ),
        ]
    }
}
