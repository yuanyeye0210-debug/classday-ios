import Foundation

/// Preferred App Group. Entitlements still request this id so a signer registers one.
/// A free Apple ID often cannot claim the exact string: Apple answers
/// "An Application Group with Identifier '…' is not available" when another team owns it.
/// Sideloadly, SideStore, AltStore, and Impactor then register a team-scoped id and write
/// that id into both provisioning profiles. Both targets must discover the same id.
public enum AppGroup {
    public static let identifier = "group.com.classday.shared"
    public static let storeFileName = "classday-store.json"
}

public struct ProvisionSnapshot: Equatable, Sendable {
    public var teamIdentifier: String?
    public var bundleIdentifier: String?
    public var applicationGroups: [String]

    public init(teamIdentifier: String?, bundleIdentifier: String?, applicationGroups: [String]) {
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationGroups = applicationGroups
    }
}

public enum ProvisionProfile {
    /// `embedded.mobileprovision` is a CMS blob with one XML plist inside it.
    /// A raw XML or binary plist is accepted so tests can skip the signature wrapper.
    public static func parse(_ data: Data) -> ProvisionSnapshot? {
        guard let plist = plistData(from: data) else { return nil }
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
            return nil
        }
        let entitlements = root["Entitlements"] as? [String: Any] ?? root
        let team = sanitizedTeam(
            stringList(root["TeamIdentifier"]).first
                ?? entitlements["com.apple.developer.team-identifier"] as? String
                ?? stringList(root["ApplicationIdentifierPrefix"]).first
        )
        let applicationIdentifier = entitlements["application-identifier"] as? String
        let groups = stringList(entitlements["com.apple.security.application-groups"]).compactMap(sanitizedGroup)
        return ProvisionSnapshot(
            teamIdentifier: team,
            bundleIdentifier: bundleIdentifier(applicationIdentifier: applicationIdentifier, teamIdentifier: team),
            applicationGroups: groups
        )
    }

    static func plistData(from data: Data) -> Data? {
        if data.starts(with: Data("bplist".utf8)) { return data }
        if let xml = xmlSlice(in: data) { return xml }
        if data.starts(with: Data("<?xml".utf8)) || data.starts(with: Data("<plist".utf8)) { return data }
        return nil
    }

    static func xmlSlice(in data: Data) -> Data? {
        let startToken = Data("<?xml".utf8)
        let endToken = Data("</plist>".utf8)
        guard let start = data.range(of: startToken),
              let end = data.range(of: endToken, in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}

public struct AppGroupCandidateInput: Equatable, Sendable {
    public var preferredIdentifier: String
    public var appBundleIdentifier: String?
    public var teamIdentifier: String?
    public var appGroups: [String]
    public var widgetGroups: [String]
    /// True when that target's `embedded.mobileprovision` was found and parsed.
    public var appProfileFound: Bool
    public var widgetProfileFound: Bool

    public init(
        preferredIdentifier: String,
        appBundleIdentifier: String?,
        teamIdentifier: String?,
        appGroups: [String],
        widgetGroups: [String],
        appProfileFound: Bool,
        widgetProfileFound: Bool
    ) {
        self.preferredIdentifier = preferredIdentifier
        self.appBundleIdentifier = appBundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.appGroups = appGroups
        self.widgetGroups = widgetGroups
        self.appProfileFound = appProfileFound
        self.widgetProfileFound = widgetProfileFound
    }
}

public enum AppGroupCandidates {
    /// Stable order for both processes. `group.com.classday.shared` is always first when it is a valid group id.
    /// Groups present in both profiles come next, then the team-id and bundle-id forms free-account signers register,
    /// then groups that only one profile listed.
    public static func ordered(_ input: AppGroupCandidateInput) -> [String] {
        var list: [String] = []
        appendUnique(sanitizedGroup(input.preferredIdentifier), to: &list)

        let appGroups = input.appGroups.compactMap(sanitizedGroup)
        let widgetGroups = input.widgetGroups.compactMap(sanitizedGroup)
        let widgetSet = Set(widgetGroups)
        for group in appGroups where widgetSet.contains(group) {
            appendUnique(group, to: &list)
        }
        for group in derived(input) {
            appendUnique(group, to: &list)
        }
        for group in appGroups {
            appendUnique(group, to: &list)
        }
        for group in widgetGroups {
            appendUnique(group, to: &list)
        }
        return list
    }

    /// A candidate may be used only when both targets can be expected to accept it.
    /// One-sided profile groups are not used: the app would write a file the widget cannot open.
    public static func isShared(_ identifier: String, input: AppGroupCandidateInput) -> Bool {
        guard sanitizedGroup(identifier) != nil else { return false }
        let appGroups = input.appGroups.compactMap(sanitizedGroup)
        let widgetGroups = input.widgetGroups.compactMap(sanitizedGroup)
        switch (input.appProfileFound, input.widgetProfileFound) {
        case (true, true):
            if appGroups.isEmpty && widgetGroups.isEmpty { return true }
            // Sideloadly often embeds a widget profile with no
            // application-groups key even when the widget can open the
            // app's group. Treat an empty list as "unknown", not "none".
            if appGroups.isEmpty { return widgetGroups.contains(identifier) }
            if widgetGroups.isEmpty { return appGroups.contains(identifier) }
            return appGroups.contains(identifier) && widgetGroups.contains(identifier)
        case (false, false):
            return true
        case (true, false):
            return appGroups.isEmpty || appGroups.contains(identifier)
        case (false, true):
            return widgetGroups.isEmpty || widgetGroups.contains(identifier)
        }
    }

    public static func select(candidates: [String], input: AppGroupCandidateInput, isUsable: (String) -> Bool) -> String? {
        candidates.first { isShared($0, input: input) && isUsable($0) }
    }

    static func derived(_ input: AppGroupCandidateInput) -> [String] {
        var list: [String] = []
        let team = input.teamIdentifier.flatMap(sanitizedTeam)
        let bundle = input.appBundleIdentifier.flatMap(sanitizedBundle)
        if let preferred = sanitizedGroup(input.preferredIdentifier), let team {
            appendUnique(sanitizedGroup(preferred + "." + team), to: &list)
            if preferred.hasPrefix("group.") {
                let rest = preferred.dropFirst("group.".count)
                appendUnique(sanitizedGroup("group." + team + "." + rest), to: &list)
            }
        }
        if let bundle {
            appendUnique(sanitizedGroup("group." + bundle), to: &list)
            if let team {
                appendUnique(sanitizedGroup("group." + bundle + "." + team), to: &list)
                appendUnique(sanitizedGroup("group." + team + "." + bundle), to: &list)
            }
        }
        return list
    }
}

public struct AppGroupBundleFiles: Equatable, Sendable {
    public var appBundle: URL?
    public var widgetBundle: URL?
    public var appInfoPlist: URL?
    public var widgetInfoPlist: URL?
    public var appProvision: URL?
    public var widgetProvision: URL?

    public init(
        appBundle: URL?,
        widgetBundle: URL?,
        appInfoPlist: URL?,
        widgetInfoPlist: URL?,
        appProvision: URL?,
        widgetProvision: URL?
    ) {
        self.appBundle = appBundle
        self.widgetBundle = widgetBundle
        self.appInfoPlist = appInfoPlist
        self.widgetInfoPlist = widgetInfoPlist
        self.appProvision = appProvision
        self.widgetProvision = widgetProvision
    }
}

public enum AppGroupBundleLayout {
    /// The running bundle is either `Classday.app` or `Classday.app/PlugIns/ClassdayWidget.appex`.
    /// Both targets walk to the same two profiles so the candidate list does not depend on who is asking.
    public static func locate(bundleURL: URL, fileManager: FileManager = .default) -> AppGroupBundleFiles {
        // macOS temporary directories are /var → /private/var. Directory listings resolve the
        // symlink and the URL we were given often does not, so both entry points must canonicalize.
        let bundle = canonical(bundleURL)
        let app: URL?
        let widget: URL?
        if bundle.pathExtension.lowercased() == "appex" {
            widget = bundle
            let plugins = bundle.deletingLastPathComponent()
            if plugins.lastPathComponent.lowercased() == "plugins" {
                let parent = plugins.deletingLastPathComponent()
                app = parent.pathExtension.lowercased() == "app" ? parent : nil
            } else {
                app = nil
            }
        } else if bundle.pathExtension.lowercased() == "app" {
            app = bundle
            widget = widgetAppex(in: bundle, fileManager: fileManager)
        } else {
            app = nil
            widget = nil
        }
        return AppGroupBundleFiles(
            appBundle: app,
            widgetBundle: widget,
            appInfoPlist: existingFile(app?.appendingPathComponent("Info.plist"), fileManager: fileManager),
            widgetInfoPlist: existingFile(widget?.appendingPathComponent("Info.plist"), fileManager: fileManager),
            appProvision: existingFile(app?.appendingPathComponent("embedded.mobileprovision"), fileManager: fileManager),
            widgetProvision: existingFile(widget?.appendingPathComponent("embedded.mobileprovision"), fileManager: fileManager)
        )
    }

    private static func widgetAppex(in app: URL, fileManager: FileManager) -> URL? {
        let directories = ["PlugIns", "Plugins"].map { app.appendingPathComponent($0, isDirectory: true) }
        var appexes: [URL] = []
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let children = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            appexes.append(contentsOf: children.filter { $0.pathExtension.lowercased() == "appex" })
        }
        appexes.sort { $0.lastPathComponent < $1.lastPathComponent }
        if let named = appexes.first(where: { $0.lastPathComponent == "ClassdayWidget.appex" }) {
            return canonical(named)
        }
        return appexes.first.map(canonical)
    }
}

private func canonical(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
}

public struct AppGroupResolution: Equatable, Sendable {
    public var identifier: String?
    public var candidates: [String]
    /// Sanitized groups from either parsed profile, app profile first.
    public var profileGroups: [String]

    public init(identifier: String?, candidates: [String], profileGroups: [String]) {
        self.identifier = identifier
        self.candidates = candidates
        self.profileGroups = profileGroups
    }
}

public enum AppGroupResolver {
    public static func resolve(
        bundleURL: URL,
        preferredIdentifier: String = AppGroup.identifier,
        fileManager: FileManager = .default,
        isUsable: (String) -> Bool
    ) -> AppGroupResolution {
        let files = AppGroupBundleLayout.locate(bundleURL: bundleURL, fileManager: fileManager)
        let appParsed = files.appProvision.flatMap { url in
            (try? Data(contentsOf: url)).flatMap(ProvisionProfile.parse)
        }
        let widgetParsed = files.widgetProvision.flatMap { url in
            (try? Data(contentsOf: url)).flatMap(ProvisionProfile.parse)
        }
        let infoBundle = files.appInfoPlist.flatMap { url in
            (try? Data(contentsOf: url)).flatMap(InfoPlistReader.bundleIdentifier)
        }
        let input = AppGroupCandidateInput(
            preferredIdentifier: preferredIdentifier,
            appBundleIdentifier: infoBundle ?? appParsed?.bundleIdentifier ?? widgetParsed.flatMap { hostBundleIdentifier(fromWidget: $0.bundleIdentifier) },
            teamIdentifier: appParsed?.teamIdentifier ?? widgetParsed?.teamIdentifier,
            appGroups: appParsed?.applicationGroups ?? [],
            widgetGroups: widgetParsed?.applicationGroups ?? [],
            appProfileFound: files.appProvision != nil && appParsed != nil,
            widgetProfileFound: files.widgetProvision != nil && widgetParsed != nil
        )
        let candidates = AppGroupCandidates.ordered(input)
        var profileGroups: [String] = []
        for group in (appParsed?.applicationGroups ?? []) + (widgetParsed?.applicationGroups ?? []) {
            appendUnique(group, to: &profileGroups)
        }
        return AppGroupResolution(
            identifier: AppGroupCandidates.select(candidates: candidates, input: input, isUsable: isUsable),
            candidates: candidates,
            profileGroups: profileGroups
        )
    }

    /// `com.classday.app.widget` → `com.classday.app`. Used only when the app profile did not say.
    static func hostBundleIdentifier(fromWidget bundle: String?) -> String? {
        guard let bundle = bundle.flatMap(sanitizedBundle) else { return nil }
        for suffix in [".widget", ".Widget", ".appex"] where bundle.hasSuffix(suffix) {
            let host = String(bundle.dropLast(suffix.count))
            if let sanitized = sanitizedBundle(host) { return sanitized }
        }
        return nil
    }
}

public enum InfoPlistReader {
    public static func bundleIdentifier(in data: Data) -> String? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return (root["CFBundleIdentifier"] as? String).flatMap(sanitizedBundle)
    }
}

/// Free Apple ID resigns can leave the app and the widget with different granted groups,
/// or with a group only one side's probe accepts. The app therefore mirrors a small
/// snapshot into every group it can open, and the widget reads the newest copy from any
/// group it can open. Pure file logic so it is testable off-device.
public enum WidgetSnapshotMirror {
    public static let fileName = "classday-widget-snapshot.json"

    /// Writes `data` into each container. Returns the groups that accepted the write.
    @discardableResult
    public static func publish(
        _ data: Data,
        groups: [String],
        containerURL: (String) -> URL?,
        fileManager: FileManager = .default
    ) -> [String] {
        var written: [String] = []
        for group in unique(groups) {
            guard let container = containerURL(group) else { continue }
            do {
                try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
                try data.write(to: container.appendingPathComponent(fileName), options: .atomic)
                written.append(group)
            } catch {
                continue
            }
        }
        return written
    }

    /// Newest readable snapshot across the containers, by modification date.
    public static func loadNewest(
        groups: [String],
        containerURL: (String) -> URL?,
        fileManager: FileManager = .default
    ) -> Data? {
        var best: (Date, Data)?
        for group in unique(groups) {
            guard let url = containerURL(group)?.appendingPathComponent(fileName),
                  let data = try? Data(contentsOf: url) else { continue }
            let modified = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            if best == nil || modified > best!.0 { best = (modified, data) }
        }
        return best?.1
    }

    private static func unique(_ groups: [String]) -> [String] {
        var list: [String] = []
        for group in groups { appendUnique(sanitizedGroup(group), to: &list) }
        return list
    }
}

/// One short line for the widget and 我的, so a screenshot tells us what the resign granted.
public enum AppGroupDiagnostics {
    public static func summary(resolution: AppGroupResolution, usable: [String]) -> String {
        let chosen = resolution.identifier ?? "无"
        let profile = resolution.profileGroups.isEmpty ? "无" : resolution.profileGroups.joined(separator: "、")
        let open = usable.isEmpty ? "无" : usable.joined(separator: "、")
        return "共享组：\(chosen)｜描述文件：\(profile)｜可读写：\(open)"
    }
}

public enum AppGroupSupport {
    /// Shown in 我的 when no shared group can be opened. Names the Sideloadly control that drops the widget.
    public static func unavailableNotice(profileGroups: [String]) -> String {
        let found: String
        if profileGroups.isEmpty {
            found = "这次安装的描述文件里没有共享组（com.apple.security.application-groups）。"
        } else {
            found = "描述文件里有「\(profileGroups.joined(separator: "、"))」，但课曜无法读写其中任何一个。"
        }
        return """
        未能访问共享 App Group。课程仍保存在本机，桌面小组件读不到。\(found)

        用 Sideloadly 和免费 Apple ID 重装：
        1. 安装方式选 Apple ID 签名，不要改 Bundle ID。主 App 和小组件必须用同一次安装、同一个账号。
        2. 高级选项里不要勾选 Remove Extensions（移除插件）。如果列出了插件，不要勾选 ClassdayWidget.appex。主 App 和小组件各占 1 个 App ID，免费账号每 7 天最多新建 10 个。
        3. Sideloadly 会把 App Group 注册到你的 Team。group.com.classday.shared 若已被占用，日志会写 An Application Group with Identifier … is not available，组名会改成带 Team ID 或 Bundle ID 的形式（例如 group.com.classday.shared.团队ID、group.团队ID.com.classday.shared、group.加上主 App 的 Bundle ID）。用同一 IPA 再装一次。课曜会从两边的描述文件里选用同一个能读写的组。
        4. 到「设置 → 通用 → VPN 与设备管理」信任该 Apple ID，然后打开课曜一次。
        """
    }
}

#if os(iOS) || os(macOS) || os(watchOS) || os(visionOS)
public enum AppGroupAccess {
    public static let probeDefaultsKey = "classday.group.probe"
    public static let probeFileName = ".classday-group-probe"

    /// A real container file round-trip proves access. A preferences-suite failure
    /// must not reject a working file container after sideload signing.
    public static func isUsable(
        _ identifier: String,
        fileManager: FileManager = .default,
        userDefaults: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) -> Bool {
        guard sanitizedGroup(identifier) != nil else { return false }
        guard let container = containerURL(for: identifier, fileManager: fileManager) else { return false }
        let token = UUID().uuidString
        let url = container.appendingPathComponent(probeFileName)
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            try Data(token.utf8).write(to: url, options: .atomic)
            let read = try String(contentsOf: url, encoding: .utf8)
            try? fileManager.removeItem(at: url)
            return read == token
        } catch {
            try? fileManager.removeItem(at: url)
            return false
        }
    }

    private static func containerURL(for identifier: String, fileManager: FileManager) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

public enum AppGroupContainer {
    private static let cachedResolution: AppGroupResolution = AppGroupResolver.resolve(
        bundleURL: Bundle.main.bundleURL,
        isUsable: { AppGroupAccess.isUsable($0) }
    )

    public static func resolution() -> AppGroupResolution {
        cachedResolution
    }

    /// Every candidate (preferred, profile, derived) this process can actually open.
    private static let cachedUsable: [String] = {
        var list: [String] = []
        if let chosen = cachedResolution.identifier { list.append(chosen) }
        for group in cachedResolution.candidates where !list.contains(group) && AppGroupAccess.isUsable(group) {
            list.append(group)
        }
        return list
    }()

    public static func usableGroups() -> [String] {
        cachedUsable
    }

    public static func diagnostics() -> String {
        AppGroupDiagnostics.summary(resolution: cachedResolution, usable: cachedUsable)
    }

    @discardableResult
    public static func publishSnapshot(_ data: Data, fileManager: FileManager = .default) -> [String] {
        let groups = cachedUsable
        for group in groups {
            UserDefaults(suiteName: group)?.set(data, forKey: WidgetStoreSnapshot.defaultsKey)
        }
        return WidgetSnapshotMirror.publish(data, groups: groups, containerURL: {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }, fileManager: fileManager)
    }

    public static func loadMirroredSnapshot(fileManager: FileManager = .default) -> Data? {
        let groups = cachedUsable
        if let file = WidgetSnapshotMirror.loadNewest(groups: groups, containerURL: {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }, fileManager: fileManager) {
            return file
        }
        for group in groups {
            if let data = UserDefaults(suiteName: group)?.data(forKey: WidgetStoreSnapshot.defaultsKey) { return data }
        }
        return nil
    }

    public static func storeURL(fileManager: FileManager = .default) -> URL? {
        guard let identifier = cachedResolution.identifier,
              let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return container.appendingPathComponent(AppGroup.storeFileName)
    }
}
#endif

private func sanitizedGroup(_ raw: String) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.hasPrefix("group."), value.count > "group.".count else { return nil }
    guard !value.contains("*"), !value.contains(" "), !value.contains("\n"), !value.contains("\t") else { return nil }
    return value
}

private func sanitizedTeam(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    guard value.count == 10, value.allSatisfy({ allowed.contains($0) }) else { return nil }
    return value
}

private func sanitizedBundle(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 220, value.contains(".") else { return nil }
    guard !value.contains("*"), !value.contains(" "), !value.contains("/"), !value.contains("\n") else { return nil }
    return value
}

private func bundleIdentifier(applicationIdentifier: String?, teamIdentifier: String?) -> String? {
    guard let applicationIdentifier else { return nil }
    let value = applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if let teamIdentifier, value.hasPrefix(teamIdentifier + ".") {
        return sanitizedBundle(String(value.dropFirst(teamIdentifier.count + 1)))
    }
    let parts = value.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, sanitizedTeam(String(parts[0])) != nil else { return nil }
    return sanitizedBundle(String(parts[1]))
}

private func stringList(_ value: Any?) -> [String] {
    if let list = value as? [String] { return list }
    if let list = value as? [Any] { return list.compactMap { $0 as? String } }
    if let one = value as? String { return [one] }
    return []
}

private func appendUnique(_ value: String?, to list: inout [String]) {
    guard let value, !list.contains(value) else { return }
    list.append(value)
}

private func existingFile(_ url: URL?, fileManager: FileManager) -> URL? {
    guard let url, fileManager.fileExists(atPath: url.path) else { return nil }
    return url
}
