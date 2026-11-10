import SwiftUI
import PhotosUI
import Vision
import ClassdayCore

struct OCRImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picker: PhotosPickerItem?
    @State private var lines: [String] = []
    @State private var draft = ""
    @State private var skippedCount = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("识别结果可以改，确认后才写入课表。每行一门课，要带星期和时间，例如「高等数学 周一 08:00-09:40」；认不出星期或时间的行会被跳过。")
                    .font(.subheadline)
                PhotosPicker(selection: $picker, matching: .images) {
                    Label("从相册选择课表照片", systemImage: "text.viewfinder")
                }
                TextEditor(text: $draft)
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                Button("按识别文本导入") { importDraft() }
                    .buttonStyle(.borderedProminent)
                if skippedCount > 0 {
                    Text("有 \(skippedCount) 行没认出星期或时间，已跳过，可以改好格式后重新导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("识别课表")
            .onChange(of: picker) { _, item in
                Task { await recognize(item) }
            }
        }
    }

    private func importDraft() {
        let weekDates = SemesterCalendar.dates(inWeek: 1, semester: model.document.semester, calendar: model.calendar)
        var events: [String] = []
        var skipped = 0
        for rawLine in draft.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let parsed = Self.parseLine(line),
                  parsed.weekday >= 1, parsed.weekday <= weekDates.count else {
                skipped += 1
                continue
            }
            let day = weekDates[parsed.weekday - 1]
            let parts = model.calendar.dateComponents([.year, .month, .day], from: day)
            func stamp(_ time: (hour: Int, minute: Int)) -> String {
                String(format: "%04d%02d%02dT%02d%02d00",
                       parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, time.hour, time.minute)
            }
            events.append("BEGIN:VEVENT\nSUMMARY:\(Self.escapeICS(parsed.name))\nDTSTART:\(stamp(parsed.start))\nDTEND:\(stamp(parsed.end))\nEND:VEVENT")
        }
        skippedCount = skipped
        let imported = ICSImporter.parse(events.joined(separator: "\n"), calendar: model.calendar, totalWeeks: model.document.semester.totalWeeks)
        if imported.courses.isEmpty && imported.exams.isEmpty {
            model.banner = "没有认出带星期和时间的课程行，请按格式改一改再试"
        } else {
            model.importCalendar(imported)
            if skipped > 0 {
                model.banner = "已导入，另有 \(skipped) 行没认出星期/时间被跳过"
            }
            dismiss()
        }
    }

    /// Extracts weekday + time range from one OCR line; the rest is the course name.
    private static func parseLine(_ line: String) -> (name: String, weekday: Int, start: (hour: Int, minute: Int), end: (hour: Int, minute: Int))? {
        let weekdayTokens: [(String, Int)] = [
            ("星期一", 1), ("周一", 1), ("星期二", 2), ("周二", 2),
            ("星期三", 3), ("周三", 3), ("星期四", 4), ("周四", 4),
            ("星期五", 5), ("周五", 5), ("星期六", 6), ("周六", 6),
            ("星期日", 7), ("周日", 7), ("星期天", 7), ("周天", 7),
        ]
        var weekday: Int?
        var rest = line
        for (token, day) in weekdayTokens where rest.contains(token) {
            weekday = day
            rest = rest.replacingOccurrences(of: token, with: " ")
            break
        }
        guard let weekday else { return nil }
        let pattern = #"(\d{1,2}):(\d{2})\s*[-–~]\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              match.numberOfRanges == 5 else { return nil }
        let ns = rest as NSString
        func intAt(_ index: Int) -> Int { Int(ns.substring(with: match.range(at: index))) ?? 0 }
        let name = rest.replacingOccurrences(of: ns.substring(with: match.range), with: " ")
            .trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? line : name, weekday, (intAt(1), intAt(2)), (intAt(3), intAt(4)))
    }

    private static func escapeICS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func recognize(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue)) ?? .up
        let text = await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try? handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
        lines = text
        draft = text.joined(separator: "\n")
    }
}
