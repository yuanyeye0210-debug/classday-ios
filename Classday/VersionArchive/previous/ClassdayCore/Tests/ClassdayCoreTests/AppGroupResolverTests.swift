import XCTest
import ClassdayCore

final class AppGroupResolverTests: XCTestCase {
    private let team = "AB12CD34EF"
    private let preferred = "group.com.classday.shared"
    private let rewritten = "group.com.classday.shared.AB12CD34EF"

    func testParsesGroupsOutOfACMSWrappedProvision() throws {
        let xml = provisionXML(
            team: team,
            applicationIdentifier: "\(team).com.classday.app",
            groups: [rewritten, "com.not-a-group", "group.*", "  group.com.classday.shared  "]
        )
        var wrapped = Data([0x30, 0x82, 0x01, 0x00])
        wrapped.append(Data("MIME-Version: 1.0\n".utf8))
        wrapped.append(contentsOf: xml.utf8)
        wrapped.append(Data("\n%%EOF".utf8))

        let parsed = try XCTUnwrap(ProvisionProfile.parse(wrapped))
        XCTAssertEqual(parsed.teamIdentifier, team)
        XCTAssertEqual(parsed.bundleIdentifier, "com.classday.app")
        XCTAssertEqual(parsed.applicationGroups, [rewritten, preferred])
        XCTAssertNil(ProvisionProfile.parse(Data("not a profile".utf8)))
    }

    func testPreferredIsFirstAndBothBundlesSelectTheRewrittenGroup() throws {
        let root = try TestSupport.temporaryDirectory()
        let app = try installBundle(
            at: root,
            appGroups: [rewritten],
            widgetGroups: [rewritten, "group.com.classday.app.widget"],
            appBundleIdentifier: "com.classday.app",
            widgetBundleIdentifier: "com.classday.app.widget"
        )
        let fromApp = AppGroupResolver.resolve(bundleURL: app.app, isUsable: { $0 == self.rewritten || $0 == self.preferred })
        let fromWidget = AppGroupResolver.resolve(bundleURL: app.widget, isUsable: { $0 == self.rewritten || $0 == self.preferred })

        XCTAssertEqual(fromApp.candidates.first, preferred)
        XCTAssertEqual(fromApp.candidates, fromWidget.candidates)
        XCTAssertEqual(fromApp.identifier, rewritten)
        XCTAssertEqual(fromWidget.identifier, rewritten)
        XCTAssertTrue(fromApp.candidates.contains("group.AB12CD34EF.com.classday.shared"))
        XCTAssertTrue(fromApp.candidates.contains("group.com.classday.app"))
        XCTAssertTrue(fromApp.candidates.contains("group.com.classday.app.AB12CD34EF"))
        XCTAssertTrue(fromApp.candidates.contains("group.AB12CD34EF.com.classday.app"))
        XCTAssertEqual(fromApp.candidates.filter { $0 == rewritten }.count, 1)
    }

    func testEmptyWidgetProfileStillSelectsTheAppGroup() throws {
        let root = try TestSupport.temporaryDirectory()
        let app = try installBundle(
            at: root,
            appGroups: [rewritten],
            widgetGroups: [],
            appBundleIdentifier: "com.classday.app",
            widgetBundleIdentifier: "com.classday.app.widget"
        )
        let fromApp = AppGroupResolver.resolve(bundleURL: app.app, isUsable: { $0 == self.rewritten })
        let fromWidget = AppGroupResolver.resolve(bundleURL: app.widget, isUsable: { $0 == self.rewritten })
        XCTAssertEqual(fromApp.identifier, rewritten)
        XCTAssertEqual(fromWidget.identifier, rewritten)
    }

    func testOneSidedGroupsAreNotSelected() throws {
        let root = try TestSupport.temporaryDirectory()
        let app = try installBundle(
            at: root,
            appGroups: ["group.com.classday.shared.AB12CD34EF"],
            widgetGroups: ["group.com.classday.app.AB12CD34EF"],
            appBundleIdentifier: "com.classday.app",
            widgetBundleIdentifier: "com.classday.app.widget"
        )
        let resolution = AppGroupResolver.resolve(bundleURL: app.app, isUsable: { _ in true })
        XCTAssertNil(resolution.identifier)
        XCTAssertEqual(
            resolution.profileGroups,
            ["group.com.classday.shared.AB12CD34EF", "group.com.classday.app.AB12CD34EF"]
        )
    }

    func testNoProfileUsesPreferredWhenItWorks() throws {
        let root = try TestSupport.temporaryDirectory()
        let appURL = root.appendingPathComponent("Classday.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try infoPlist(bundleIdentifier: "com.example.classday").write(to: appURL.appendingPathComponent("Info.plist"))
        let resolution = AppGroupResolver.resolve(bundleURL: appURL, isUsable: { $0 == self.preferred })
        XCTAssertEqual(resolution.candidates.first, preferred)
        XCTAssertEqual(resolution.identifier, preferred)
        XCTAssertTrue(resolution.candidates.contains("group.com.example.classday"))
        XCTAssertEqual(
            AppGroupResolver.resolve(bundleURL: appURL, isUsable: { _ in false }).identifier,
            nil
        )
    }

    func testLayoutFromAppAndAppexSeesTheSameProfiles() throws {
        let root = try TestSupport.temporaryDirectory()
        let installed = try installBundle(
            at: root,
            appGroups: [preferred],
            widgetGroups: [preferred],
            appBundleIdentifier: "com.classday.app",
            widgetBundleIdentifier: "com.classday.app.widget"
        )
        let fromApp = AppGroupBundleLayout.locate(bundleURL: installed.app)
        let fromWidget = AppGroupBundleLayout.locate(bundleURL: installed.widget)
        XCTAssertEqual(fromApp, fromWidget)
        XCTAssertEqual(fromApp.appProvision?.lastPathComponent, "embedded.mobileprovision")
        XCTAssertEqual(fromApp.widgetProvision?.lastPathComponent, "embedded.mobileprovision")
        XCTAssertNotEqual(fromApp.appProvision, fromApp.widgetProvision)
    }

    func testUnavailableNoticeNamesTheSideloadlySetting() {
        let empty = AppGroupSupport.unavailableNotice(profileGroups: [])
        XCTAssertTrue(empty.contains("没有共享组"))
        XCTAssertTrue(empty.contains("Remove Extensions"))
        XCTAssertTrue(empty.contains("ClassdayWidget.appex"))
        XCTAssertTrue(empty.contains("免费"))
        XCTAssertTrue(empty.contains("group.com.classday.shared"))
        XCTAssertTrue(empty.contains("is not available"))
        XCTAssertTrue(empty.contains("VPN 与设备管理"))

        let found = AppGroupSupport.unavailableNotice(profileGroups: [rewritten])
        XCTAssertTrue(found.contains(rewritten))
        XCTAssertFalse(found.contains("没有共享组"))
    }

    func testSnapshotMirrorWritesEveryOpenGroupAndReadsNewest() throws {
        let root = try TestSupport.temporaryDirectory()
        let firstDir = root.appendingPathComponent("a", isDirectory: true)
        let secondDir = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDir, withIntermediateDirectories: true)
        let map = ["group.a": firstDir, "group.b": secondDir]
        let first = Data("one".utf8)
        let second = Data("two".utf8)
        XCTAssertEqual(
            WidgetSnapshotMirror.publish(first, groups: ["group.a", "group.b", "not-a-group"], containerURL: { map[$0] }),
            ["group.a", "group.b"]
        )
        let firstURL = firstDir.appendingPathComponent(WidgetSnapshotMirror.fileName)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: firstURL.path)
        XCTAssertEqual(
            WidgetSnapshotMirror.publish(second, groups: ["group.b"], containerURL: { map[$0] }),
            ["group.b"]
        )
        let secondURL = secondDir.appendingPathComponent(WidgetSnapshotMirror.fileName)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: secondURL.path)
        XCTAssertEqual(WidgetSnapshotMirror.loadNewest(groups: ["group.a", "group.b"], containerURL: { map[$0] }), second)
        XCTAssertEqual(WidgetSnapshotMirror.loadNewest(groups: ["group.a"], containerURL: { map[$0] }), first)
        XCTAssertNil(WidgetSnapshotMirror.loadNewest(groups: ["group.missing"], containerURL: { map[$0] }))
    }

    func testDiagnosticsSummarizeChosenAndUsableGroups() {
        let resolution = AppGroupResolution(identifier: nil, candidates: [preferred], profileGroups: [rewritten])
        let text = AppGroupDiagnostics.summary(resolution: resolution, usable: [])
        XCTAssertTrue(text.contains("共享组：无"))
        XCTAssertTrue(text.contains(rewritten))
        XCTAssertTrue(text.contains("可读写：无"))
        XCTAssertEqual(
            AppGroupDiagnostics.summary(
                resolution: AppGroupResolution(identifier: rewritten, candidates: [rewritten], profileGroups: [rewritten]),
                usable: [rewritten]
            ),
            "共享组：\(rewritten)｜描述文件：\(rewritten)｜可读写：\(rewritten)"
        )
    }
}

private extension AppGroupResolverTests {
    func installBundle(
        at root: URL,
        appGroups: [String],
        widgetGroups: [String],
        appBundleIdentifier: String,
        widgetBundleIdentifier: String
    ) throws -> (app: URL, widget: URL) {
        let app = root.appendingPathComponent("Classday.app", isDirectory: true)
        let widget = app
            .appendingPathComponent("PlugIns", isDirectory: true)
            .appendingPathComponent("ClassdayWidget.appex", isDirectory: true)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try infoPlist(bundleIdentifier: appBundleIdentifier).write(to: app.appendingPathComponent("Info.plist"))
        try infoPlist(bundleIdentifier: widgetBundleIdentifier).write(to: widget.appendingPathComponent("Info.plist"))
        let appProvision = provisionXML(
            team: team,
            applicationIdentifier: "\(team).\(appBundleIdentifier)",
            groups: appGroups
        )
        let widgetProvision = provisionXML(
            team: team,
            applicationIdentifier: "\(team).\(widgetBundleIdentifier)",
            groups: widgetGroups
        )
        try Data(appProvision.utf8).write(to: app.appendingPathComponent("embedded.mobileprovision"))
        try Data(widgetProvision.utf8).write(to: widget.appendingPathComponent("embedded.mobileprovision"))
        return (app, widget)
    }

    func infoPlist(bundleIdentifier: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleIdentifier)</string>
        </dict></plist>
        """.utf8)
    }

    func provisionXML(team: String, applicationIdentifier: String, groups: [String]) -> String {
        let groupXML = groups.map { "<string>\($0)</string>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>TeamIdentifier</key>
          <array><string>\(team)</string></array>
          <key>Entitlements</key>
          <dict>
            <key>application-identifier</key>
            <string>\(applicationIdentifier)</string>
            <key>com.apple.developer.team-identifier</key>
            <string>\(team)</string>
            <key>com.apple.security.application-groups</key>
            <array>\(groupXML)</array>
            <key>get-task-allow</key>
            <true/>
          </dict>
        </dict>
        </plist>
        """
    }
}
