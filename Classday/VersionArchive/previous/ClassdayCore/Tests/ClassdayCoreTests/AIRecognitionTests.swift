import Foundation
import XCTest
import ClassdayCore

/// Task 4 (2.8.0 P0-2): 统一 AI 识别信封 AIRecognition 的测试。
/// 先写测试再写实现（TDD）；输入与 V2FeatureTests 里同名解析器测试保持一致。
final class AIRecognitionTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testGradeRecognitionWrapsSchemeAndKeepsRawText() {
        let json = #"{"scale": 20, "components": ["P", "TEST60", "EX1", "EX2"], "branches": [[{"component": "P", "weight": 0.25}, {"component": "TEST60", "weight": 0.25}, {"component": "EX1", "weight": 0.5}], [{"component": "P", "weight": 0.25}, {"component": "EX1", "weight": 0.75}], [{"component": "P", "weight": 0.25}, {"component": "EX2", "weight": 0.75}]]}"#
        guard let result = AIRecognition.parse(json, source: .grade) else {
            XCTFail("grade 识别应返回结果")
            return
        }
        XCTAssertEqual(result.source, .grade)
        XCTAssertEqual(result.rawText, json)
        XCTAssertNil(result.confidence)
        guard let expected = GradeSchemeParser.parse(json) else {
            XCTFail("同一份 JSON 应能被 GradeSchemeParser 解析")
            return
        }
        XCTAssertEqual(result.payload, .grade(expected))
        if case .grade(let scheme) = result.payload {
            XCTAssertEqual(scheme.scale, 20)
            XCTAssertEqual(scheme.components.count, 4)
            XCTAssertEqual(scheme.branches.count, 3)
        } else {
            XCTFail("payload 应为 grade(GradeScheme)")
        }
    }

    func testHolidayRecognitionWrapsPeriods() {
        let text = #"{"holidays": [{"name": "寒假", "start": "2027-01-18", "end": "2027-02-21"}, {"name": "坏数据", "start": "x", "end": "y"}]}"#
        guard let result = AIRecognition.parse(text, source: .holiday, calendar: calendar) else {
            XCTFail("holiday 识别应返回结果")
            return
        }
        XCTAssertEqual(result.source, .holiday)
        XCTAssertEqual(result.rawText, text)
        XCTAssertNil(result.confidence)
        if case .holidays(let periods) = result.payload {
            XCTAssertEqual(periods.count, 1)
            XCTAssertEqual(periods[0].name, "寒假")
            XCTAssertEqual(periods[0].startDate, "2027-01-18")
            XCTAssertEqual(periods[0].endDate, "2027-02-21")
        } else {
            XCTFail("payload 应为 holidays([HolidayPeriod])")
        }
    }

    func testCancellationRecognitionMatchesCourseAndScope() {
        let document = DemoData.makeDocument()
        let course = document.courses[0]
        let json = "{\"date\": \"2026-11-11\", \"course\": \"" + course.name + "\", \"scope\": \"am\", \"reason\": \"大风\"}"
        guard let result = AIRecognition.parse(json, source: .cancellation, courses: document.courses, calendar: calendar) else {
            XCTFail("cancellation 识别应返回结果")
            return
        }
        XCTAssertEqual(result.source, .cancellation)
        XCTAssertEqual(result.rawText, json)
        XCTAssertNil(result.confidence)
        if case .cancellation(let draft) = result.payload {
            XCTAssertEqual(draft.date, "2026-11-11")
            XCTAssertEqual(draft.courseID, course.id)
            XCTAssertEqual(draft.courseName, course.name)
            XCTAssertEqual(draft.scope, "am")
            XCTAssertEqual(draft.reason, "大风")
            XCTAssertTrue(draft.courseMatched)
        } else {
            XCTFail("payload 应为 cancellation(CancellationDraft)")
        }
    }

    func testRecognitionReturnsNilForGarbage() {
        let garbage = "这张图里没有记分规则"
        XCTAssertNil(AIRecognition.parse(garbage, source: .grade))
        XCTAssertNil(AIRecognition.parse(garbage, source: .holiday, calendar: calendar))
        XCTAssertNil(AIRecognition.parse(garbage, source: .cancellation, courses: DemoData.makeDocument().courses, calendar: calendar))
    }

    func testRecognitionReturnsNilWhenHolidayAIYieldsNothing() {
        XCTAssertNil(AIRecognition.parse(#"{"holidays": []}"#, source: .holiday, calendar: calendar))
        XCTAssertNil(AIRecognition.parse(#"{"holidays": [{"name": "坏数据", "start": "x", "end": "y"}]}"#, source: .holiday, calendar: calendar))
        XCTAssertNil(AIRecognition.parse("这张图里没有假期", source: .holiday, calendar: calendar))
    }

    /// 纯度回归钉子（Task 6）：`AIRecognition.parse` 是纯函数——只返回
    /// 值类型结果，不写 Store、不写文件；写入只发生在 UI 确认之后。
    /// 同一输入调两次应得到可重复的结果。注意假期源只能字段级比较：
    /// `HolidayImporter.parseAI` 每次调用都给每个时段 mint 一个新的 UUID
    /// （`ScheduleExtras.swift` 里 `HolidayPeriod(id: UUID(), ...)`），
    /// 所以两次调用的 `HolidayPeriod` 整体不相等；这里比较个数、名称与
    /// 起止日期。记分规则与停课源是确定性的（`GradeScheme` 不带 UUID，
    /// `CancellationDraft.courseID` 来自匹配到的课程），可以整体相等。
    /// 本测试不含任何 Store / 文件写操作。
    func testParseNeverWritesToStore() {
        // 记分规则：同一输入两次调用，结果完全相等。
        let gradeJSON = #"{"scale": 20, "components": ["P", "TEST60", "EX1", "EX2"], "branches": [[{"component": "P", "weight": 0.25}, {"component": "TEST60", "weight": 0.25}, {"component": "EX1", "weight": 0.5}], [{"component": "P", "weight": 0.25}, {"component": "EX1", "weight": 0.75}], [{"component": "P", "weight": 0.25}, {"component": "EX2", "weight": 0.75}]]}"#
        guard let firstGrade = AIRecognition.parse(gradeJSON, source: .grade),
              let secondGrade = AIRecognition.parse(gradeJSON, source: .grade) else {
            XCTFail("grade 识别应返回结果")
            return
        }
        XCTAssertEqual(firstGrade, secondGrade)

        // 假期：字段级比较（个数、名称、起止日期），不比较整体相等，
        // 因为每次 parseAI 都会 mint 新的 UUID。
        let holidayText = #"{"holidays": [{"name": "寒假", "start": "2027-01-18", "end": "2027-02-21"}, {"name": "坏数据", "start": "x", "end": "y"}]}"#
        guard let firstHoliday = AIRecognition.parse(holidayText, source: .holiday, calendar: calendar),
              let secondHoliday = AIRecognition.parse(holidayText, source: .holiday, calendar: calendar) else {
            XCTFail("holiday 识别应返回结果")
            return
        }
        XCTAssertEqual(firstHoliday.source, secondHoliday.source)
        XCTAssertEqual(firstHoliday.rawText, secondHoliday.rawText)
        XCTAssertNil(firstHoliday.confidence)
        XCTAssertNil(secondHoliday.confidence)
        guard case .holidays(let firstPeriods) = firstHoliday.payload,
              case .holidays(let secondPeriods) = secondHoliday.payload else {
            XCTFail("holiday payload 应为 holidays([HolidayPeriod])")
            return
        }
        XCTAssertEqual(firstPeriods.count, secondPeriods.count)
        for (first, second) in zip(firstPeriods, secondPeriods) {
            XCTAssertEqual(first.name, second.name)
            XCTAssertEqual(first.startDate, second.startDate)
            XCTAssertEqual(first.endDate, second.endDate)
        }

        // 停课：同一输入两次调用，结果完全相等。
        let document = DemoData.makeDocument()
        let course = document.courses[0]
        let cancellationJSON = "{\"date\": \"2026-11-11\", \"course\": \"" + course.name + "\", \"scope\": \"am\", \"reason\": \"大风\"}"
        guard let firstCancellation = AIRecognition.parse(cancellationJSON, source: .cancellation, courses: document.courses, calendar: calendar),
              let secondCancellation = AIRecognition.parse(cancellationJSON, source: .cancellation, courses: document.courses, calendar: calendar) else {
            XCTFail("cancellation 识别应返回结果")
            return
        }
        XCTAssertEqual(firstCancellation, secondCancellation)
    }

    func testRecognitionResultRoundTripsThroughJSON() throws {
        let document = DemoData.makeDocument()
        let course = document.courses[0]
        let json = "{\"date\": \"2026-11-11\", \"course\": \"" + course.name + "\", \"scope\": \"am\", \"reason\": \"大风\"}"
        guard let result = AIRecognition.parse(json, source: .cancellation, courses: document.courses, calendar: calendar) else {
            XCTFail("cancellation 识别应返回结果")
            return
        }
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(AIRecognitionResult.self, from: data)
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.source, .cancellation)
        XCTAssertEqual(decoded.rawText, json)
        XCTAssertNil(decoded.confidence)
        if case .cancellation(let draft) = decoded.payload {
            XCTAssertEqual(draft.courseName, course.name)
            XCTAssertEqual(draft.scope, "am")
            XCTAssertTrue(draft.courseMatched)
        } else {
            XCTFail("解码后 payload 应为 cancellation(CancellationDraft)")
        }
    }
}
