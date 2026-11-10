import SwiftUI
import UIKit
import CoreImage
import CoreHaptics
import CoreMotion
import MapKit
import UniformTypeIdentifiers
import ClassdayCore

struct ClassdayChrome: Equatable {
    var theme: ClassdayTheme
    var tier: PerformanceTier
    var allowsShader: Bool
    var allowsMotion: Bool
    var allowsParticles: Bool

    static func resolve(choice: AppearanceChoice, reduceMotion: Bool, lowPower: Bool) -> ClassdayChrome {
        let tier = ClassdayThemes.effectiveTier(selected: choice.performance, lowPower: lowPower, reduceMotion: reduceMotion)
        let rich = tier != .saver
        return ClassdayChrome(
            theme: choice.theme,
            tier: tier,
            allowsShader: rich && choice.theme.usesShader,
            allowsMotion: rich && choice.theme.usesMotion && !reduceMotion,
            allowsParticles: rich && tier == .high && choice.theme.specialLayout == "aurora"
        )
    }
}

private struct ClassdayChromeKey: EnvironmentKey {
    static let defaultValue = ClassdayChrome.resolve(choice: .standard, reduceMotion: false, lowPower: false)
}

extension EnvironmentValues {
    var classdayChrome: ClassdayChrome {
        get { self[ClassdayChromeKey.self] }
        set { self[ClassdayChromeKey.self] = newValue }
    }
}

enum ThemeHaptics {
    private static var engine: CHHapticEngine?

    static func play(_ name: String) {
        if playCore(name) { return }
        switch name {
        case "electric", "metal":
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        case "soft", "glass":
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case "particle", "glide":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private static func playCore(_ name: String) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                try engine?.start()
            }
            let sharpness: Float
            let intensity: Float
            switch name {
            case "electric": sharpness = 0.9; intensity = 1
            case "metal": sharpness = 0.7; intensity = 0.9
            case "soft", "glass": sharpness = 0.2; intensity = 0.45
            case "particle": sharpness = 0.4; intensity = 0.55
            default: sharpness = 0.35; intensity = 0.6
            }
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: 0)
            return true
        } catch {
            return false
        }
    }
}

struct MotionParallax: ViewModifier {
    @Environment(\.classdayChrome) private var chrome
    @State private var offset: CGSize = .zero
    @State private var manager = CMMotionManager()

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .onAppear { start() }
            .onDisappear { manager.stopDeviceMotionUpdates() }
    }

    private func start() {
        guard chrome.allowsMotion, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            offset = CGSize(width: motion.attitude.roll * 12, height: motion.attitude.pitch * 12)
        }
    }
}

struct ThemeBackground: View {
    @Environment(\.classdayChrome) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: chrome.allowsShader ? 1 / 30 : 1, paused: !chrome.allowsShader || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(chrome.theme.background.palette)
                if chrome.allowsShader {
                    Rectangle()
                        .fill(Color(chrome.theme.glow.palette).opacity(0.35))
                        .colorEffect(shader(time: time))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                } else if chrome.theme.specialLayout == "glass" {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func shader(time: TimeInterval) -> Shader {
        switch chrome.theme.specialLayout {
        case "aurora":
            ShaderLibrary.auroraFlow(.float(time))
        case "glass":
            ShaderLibrary.glassWarp(.float(time))
        default:
            ShaderLibrary.neonScan(.float(time))
        }
    }
}

struct ThemeGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.classdayChrome) private var chrome

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("外观")
                        .font(.system(size: 34, weight: .bold))
                    Text("小组件、锁屏和灵动岛跟这里同一套主题。省电和低电量会自动关掉着色器。")
                        .font(.subheadline)
                        .foregroundStyle(Color(chrome.theme.secondary.palette))
                    ForEach(ClassdayThemes.all) { theme in
                        Button {
                            model.setAppearance(AppearanceChoice(themeID: theme.id, performance: model.document.appearance.performance))
                        } label: {
                            preview(theme)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("性能")
                        .font(.headline)
                    ForEach(PerformanceTier.allCases, id: \.self) { tier in
                        Button {
                            model.setPerformance(tier)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(tier.title).font(.headline)
                                    Text(tier.detail).font(.caption)
                                }
                                Spacer()
                                if model.document.appearance.performance == tier {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(chrome.theme.card.palette)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(ThemeBackground())
            .navigationTitle("主题")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func preview(_ theme: ClassdayTheme) -> some View {
        let selected = model.document.appearance.themeID == theme.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.name).font(.headline)
                Text(theme.englishName).font(.caption)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").symbolEffect(.bounce, value: selected) }
            }
            Text(theme.tagline).font(.caption)
            HStack(spacing: 6) {
                ForEach(theme.courseAccents.prefix(4), id: \.r) { color in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(color.palette))
                        .frame(height: 28)
                }
            }
            LiveThemePreview(theme: theme)
        }
        .padding(14)
        .foregroundStyle(Color(theme.ink.palette))
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(theme.card.palette)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(theme.glow.palette), lineWidth: selected ? 2 : 0))
    }
}

private struct LiveThemePreview: View {
    var theme: ClassdayTheme

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("下一节").font(.caption2)
                Text("08:00").font(.title3.bold())
                Text("高等数学").font(.caption)
            }
            Spacer()
            Image(systemName: "clock")
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(theme.background.palette)))
    }
}

struct OrbitWeekView: View {
    @Environment(AppModel.self) private var model
    @State private var spin: Double = 0

    var body: some View {
        let items = model.occurrences(on: model.selectedDay)
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) * 0.32
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 1)
                Text(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(model.selectedDay, calendar: model.calendar)))
                    .font(.title2.bold())
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let angle = (Double(index) / Double(max(items.count, 1))) * 360 + spin
                    satellite(item)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(angle))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture().onEnded { value in
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                        spin += Double(value.translation.width)
                    }
                    Haptics.play("glide")
                }
            )
        }
        .padding(24)
    }

    private func satellite(_ item: Occurrence) -> some View {
        VStack(spacing: 2) {
            Text(ScheduleCopy.hhmm(item.start, calendar: model.calendar)).font(.caption2.bold())
            Text(item.name).font(.caption2).lineLimit(1)
        }
        .padding(8)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .rotationEffect(.degrees(-spin))
        .onTapGesture { model.openCourse(item.courseID, meeting: item.meetingID) }
    }
}

struct CubeWeekView: View {
    @Environment(AppModel.self) private var model
    @State private var yaw: Double = 0

    var body: some View {
        let items = model.occurrences(on: model.selectedDay)
        VStack(spacing: 12) {
            Text("左右轻扫，旋转到下一天")
                .font(.caption)
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 260, height: 320)
                    .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0))
                VStack(alignment: .leading, spacing: 10) {
                    Text(ScheduleCopy.weekdayName(SemesterCalendar.isoWeekday(model.selectedDay, calendar: model.calendar)))
                        .font(.headline)
                    ForEach(items.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.bold())
                            Text("\(item.timeText)  \(item.locationShort)").font(.caption2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.4).scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                        .onTapGesture { model.openCourse(item.courseID, meeting: item.meetingID) }
                    }
                }
                .padding(28)
                .frame(width: 260, height: 320)
                .rotation3DEffect(.degrees(yaw * 0.15), axis: (x: 0.2, y: 1, z: 0))
            }
            .gesture(
                DragGesture().onEnded { value in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        yaw += value.translation.width > 0 ? -28 : 28
                    }
                    model.shiftDay(by: value.translation.width > 0 ? -1 : 1)
                    Haptics.play("glass")
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CountdownDial: View {
    var progress: Double
    var label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1)))
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label).font(.caption.monospacedDigit())
            }
            .frame(width: 88, height: 88)
        }
    }
}

struct StudyDeskView: View {
    @Environment(AppModel.self) private var model
    @State private var homeworkTitle = ""
    @State private var icsURL = ""
    @State private var fenixID = FenixConfig.clientID
    @State private var fenixSecret = FenixConfig.clientSecret
    @State private var timetableName = ""
    @State private var showImporter = false
    @State private var showOCR = false

    var body: some View {
        NavigationStack {
            List {
                Section("考试") {
                    if model.document.exams.isEmpty {
                        Text("还没有考试。可以从日历或 Fénix 导入。")
                    }
                    ForEach(model.document.exams) { exam in
                        VStack(alignment: .leading) {
                            Text(exam.courseName).font(.headline)
                            Text(exam.startISO).font(.caption)
                            if let date = CivilStamp.date(from: exam.startISO, calendar: model.calendar) {
                                Text(CountdownCopy.remaining(until: date, now: Date()))
                                    .font(.caption.bold())
                            }
                        }
                    }
                }
                Section("作业") {
                    TextField("作业标题", text: $homeworkTitle)
                    Button("添加作业") {
                        guard !homeworkTitle.isEmpty else { return }
                        model.addHomework(title: homeworkTitle, courseName: "", due: Date().addingTimeInterval(86_400))
                        homeworkTitle = ""
                    }
                    ForEach(model.document.homework) { task in
                        Button {
                            model.toggleHomework(task.id)
                        } label: {
                            HStack {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                    Text(task.dueISO).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("多课表") {
                    TextField("另存为", text: $timetableName)
                    Button("保存当前课表") { model.duplicateTimetable(named: timetableName) }
                    ForEach(model.document.library) { table in
                        Button(table.name) { model.switchTimetable(to: table.id) }
                    }
                }
                Section("导入") {
                    TextField("iCal 订阅地址", text: $icsURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("订阅并导入") { Task { await subscribe() } }
                    Button("导入 .ics 或 JSON 文件") { showImporter = true }
                    Button("拍照识别课表") { showOCR = true }
                    TextField("Fénix client id", text: $fenixID)
                    SecureField("Fénix client secret", text: $fenixSecret)
                    Button("用 Fénix 登录并导入") {
                        FenixConfig.clientID = fenixID
                        FenixConfig.clientSecret = fenixSecret
                        Task { await FenixAuth.signIn(model: model) }
                    }
                    Text("在 Fénix → Personal → Manage Applications 新建应用，redirect URI 填 classday://fenix。免费 Apple ID 也能走这个网页登录。")
                        .font(.caption)
                }
                Section("分享") {
                    ShareLink(item: ShareCodec.url(for: model.document)) {
                        Label("分享课表链接", systemImage: "square.and.arrow.up")
                    }
                    TimetableQR(text: ShareCodec.url(for: model.document).absoluteString)
                }
                Section("同步") {
                    Text(CalendarSync.status)
                    Text(CloudMirror.status)
                    Button("立即写入系统日历") { CalendarSync.sync(model.document, calendar: model.calendar) }
                    Button("尝试 iCloud") { Task { await CloudMirror.push(model.document) } }
                }
            }
            .navigationTitle("学习")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, UTType(filenameExtension: "ics") ?? .data]) { result in
                if case let .success(url) = result { read(url) }
            }
            .sheet(isPresented: $showOCR) { OCRImportView() }
        }
    }

    private func subscribe() async {
        guard let url = URL(string: icsURL) else { model.banner = "地址无效"; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            model.importCalendar(ICSImporter.parse(text, calendar: model.calendar), subscribeURL: icsURL)
        } catch {
            model.banner = "没有下载到日历"
        }
    }

    private func read(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "json" {
            model.stageImport(data)
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            model.importCalendar(ICSImporter.parse(text, calendar: model.calendar))
        }
    }
}

struct TimetableQR: View {
    var text: String

    var body: some View {
        if let image = QRCode.image(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 160, height: 160)
                .accessibilityLabel("课表二维码")
        }
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum RoomNavigator {
    static func open(location: String, pin: RoomPin?) {
        let item: MKMapItem
        if let pin, let latitude = pin.latitude, let longitude = pin.longitude {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)))
            item.name = location
        }
        item.name = pin?.query ?? location
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
