import SwiftUI
import PhotosUI
import Vision
import ClassdayCore

struct OCRImportView: View {
    @Environment(\.appModel) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picker: PhotosPickerItem?
    @State private var lines: [String] = []
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("识别结果可以改，确认后才写入课表。")
                    .font(.subheadline)
                PhotosPicker(selection: $picker, matching: .images) {
                    Label("从相册选择课表照片", systemImage: "text.viewfinder")
                }
                TextEditor(text: $draft)
                    .frame(minHeight: 220)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                Button("按识别文本导入") {
                    let imported = ICSImporter.parse(draftAsICS, calendar: model.calendar)
                    if imported.courses.isEmpty && imported.exams.isEmpty {
                        model.banner = "没有认出课程，请改一改文本再试"
                    } else {
                        model.importCalendar(imported)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("识别课表")
            .onChange(of: picker) { _, item in
                Task { await recognize(item) }
            }
        }
    }

    private var draftAsICS: String {
        draft.split(separator: "\n").map { line in
            "BEGIN:VEVENT\nSUMMARY:\(line)\nDTSTART:20261102T080000\nDTEND:20261102T094000\nEND:VEVENT"
        }.joined(separator: "\n")
    }

    private func recognize(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let cgImage = image.cgImage else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        lines = text
        draft = text.joined(separator: "\n")
    }
}
