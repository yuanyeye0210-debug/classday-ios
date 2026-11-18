import Foundation

/// 统一 AI 识别信封：三个已有的 AI 解析器（记分规则 / 假期 / 停课）共用这一个入口。
/// `parse` 只做分派与包装，不改任何解析器的行为；确定性 ICS 解析
///（`HolidayImporter.parseICS`）不走这条路，保持原样调用。
/// 所有结果都是待确认草稿：`confidence` 固定为 nil（未评分，现有解析器
/// 不产出置信度），`rawText` 原样存输入文本，不做截断。
public enum AIRecognitionSource: String, Codable, Equatable, Hashable, Sendable {
    case grade
    case holiday
    case cancellation
}

public enum AIRecognitionPayload: Codable, Equatable, Sendable {
    case grade(GradeScheme)
    case holidays([HolidayPeriod])
    case cancellation(CancellationDraft)
}

public struct AIRecognitionResult: Codable, Equatable, Sendable {
    public var source: AIRecognitionSource
    public var confidence: Double?
    public var rawText: String
    public var payload: AIRecognitionPayload

    public init(source: AIRecognitionSource, confidence: Double?, rawText: String, payload: AIRecognitionPayload) {
        self.source = source
        self.confidence = confidence
        self.rawText = rawText
        self.payload = payload
    }
}

public enum AIRecognition {
    /// 按 source 分派给已有的三个解析器；解析器认不出时整个结果为 nil：
    /// grade 解析返回 nil、holiday 解析返回空数组、cancellation 解析返回 nil。
    public static func parse(_ text: String, source: AIRecognitionSource, courses: [Course] = [], calendar: Calendar = ClassdayCalendar.make()) -> AIRecognitionResult? {
        switch source {
        case .grade:
            guard let scheme = GradeSchemeParser.parse(text) else { return nil }
            return AIRecognitionResult(source: .grade, confidence: nil, rawText: text, payload: .grade(scheme))
        case .holiday:
            let periods = HolidayImporter.parseAI(text, calendar: calendar)
            guard !periods.isEmpty else { return nil }
            return AIRecognitionResult(source: .holiday, confidence: nil, rawText: text, payload: .holidays(periods))
        case .cancellation:
            guard let draft = CancellationParser.parseAI(text, courses: courses, calendar: calendar) else { return nil }
            return AIRecognitionResult(source: .cancellation, confidence: nil, rawText: text, payload: .cancellation(draft))
        }
    }
}
