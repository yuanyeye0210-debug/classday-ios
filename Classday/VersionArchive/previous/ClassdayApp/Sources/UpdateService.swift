import Foundation
import ClassdayCore

/// App-layer update check: the `latest.json` manifest first, the existing
/// GitHub Releases API path as fallback.
///
/// Task 5 wiring. Task 6 extends this service with the in-app downloader,
/// the mandatory / below-minimum alerts, the auto-check, and reporting
/// dispatch — the `decision` carried in `CheckResult` is what those need.
enum UpdateService {

    /// The `latest.json` manifest in the classday-releases archive repo.
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/latest.json")!

    /// Manifest fetch budget: one attempt, no retry — the API fallback
    /// covers any failure.
    static let manifestTimeout: TimeInterval = 15

    /// Collector endpoint for version-distribution reporting. Empty: there
    /// is no collector yet, so `UpdateReport.isEnabled(endpoint:)` is false
    /// and no reporting request is ever made. Enabling reporting later is
    /// filling in this one constant.
    static let reportEndpoint = ""

    /// UserDefaults key for the last update-check date (auto-check gate).
    static let lastCheckDateKey = "classday.update.lastCheckDate"

    /// UserDefaults key for the last version reporting saw (installed
    /// detection: stored version vs current version).
    static let lastReportedVersionKey = "classday.update.lastReportedVersion"

    /// A blocking update alert the UI must surface: either a mandatory
    /// update or a current version below the minimum supported version.
    /// Neither is ever produced for a network error or "already latest".
    enum UpdateAlertKind: Equatable {
        case mandatory(release: ReleaseEntry)
        case belowMinimum(release: ReleaseEntry)

        var release: ReleaseEntry {
            switch self {
            case let .mandatory(release): return release
            case let .belowMinimum(release): return release
            }
        }
    }

    /// Outcome of one in-app IPA download.
    enum UpdateDownloadResult: Equatable {
        /// The finished, verified IPA in the caches directory.
        case success(URL)
        /// Human-readable reason, no user data — also the reporting `error`.
        case failure(String)
    }

    /// Outcome of one update check, ready for the Settings "检查更新" row.
    struct CheckResult {
        /// The Core decision when the manifest path succeeded. `nil` when the
        /// manifest failed and the API fallback ran, or when both paths
        /// failed — the fallback has no manifest, so there is no
        /// `ReleaseEntry` to decide on.
        let decision: UpdateDecision?
        /// Row note: "新版 X", "已是最新版", or "检查失败".
        let note: String
        /// Download link shown under the row when an update is available.
        let downloadURL: URL?
    }

    /// Runs one update check against `currentVersion`
    /// (`CFBundleShortVersionString`). Never throws: every failure mode ends
    /// in either the fallback path or a "检查失败" result. Every completed
    /// check — manifest or fallback, success or failure — records the
    /// check date (the daily auto-check gate) and reports one
    /// `update_check` event.
    static func checkForUpdate(currentVersion: String) async -> CheckResult {
        let result: CheckResult
        if let manifestResult = await checkManifest(currentVersion: currentVersion) {
            result = manifestResult
        } else {
            result = await checkGitHubReleasesAPI(currentVersion: currentVersion)
        }
        recordCheckDate()
        report(.updateCheck)
        return result
    }

    /// Installed version (`CFBundleShortVersionString`), `"0"` when unreadable.
    static func currentVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Build number (`CFBundleVersion`), `"0"` when unreadable — the
    /// reporting payload's `build` field.
    static func buildVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Daily auto-check

    /// Whether a silent auto-check is due: no check has run yet, or the
    /// last check was on an earlier calendar day. A manual tap always
    /// checks (it does not consult this gate).
    static func shouldAutoCheck(now: Date = Date()) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    /// Records a completed check (manual or automatic) as the last-check
    /// date for the daily gate.
    static func recordCheckDate(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastCheckDateKey)
    }

    // MARK: - Reporting dispatch

    /// Fire-and-forget reporting dispatch. Does nothing while no endpoint
    /// is configured (`reportEndpoint` is empty). A send failure is
    /// swallowed silently — no retry, no alert, no blocking — and reporting
    /// never delays the caller.
    static func report(_ event: UpdateReportEvent) {
        guard UpdateReport.isEnabled(endpoint: reportEndpoint) else { return }
        guard let endpointURL = URL(string: reportEndpoint) else { return }
        let payload = UpdateReport(event: event, appVersion: currentVersion(), build: buildVersion()).json
        // Never issue a request with an empty body: a payload that does
        // not serialise to JSON is dropped, not posted body-less.
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task {
            var request = URLRequest(url: endpointURL, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Detects a fresh install / upgrade on launch via
    /// `installedEventIfNeeded`, reports `.installed` when one fired, and
    /// always persists the current version afterwards. First launch (no
    /// stored version) stores silently and reports nothing.
    static func reportInstalledIfNeeded() {
        let current = currentVersion()
        let stored = UserDefaults.standard.string(forKey: lastReportedVersionKey)
        if let event = UpdateReport.installedEventIfNeeded(storedVersion: stored, currentVersion: current) {
            report(event)
        }
        UserDefaults.standard.set(current, forKey: lastReportedVersionKey)
    }

    // MARK: - In-app downloader

    /// Downloads `release` in-app, driving the Core `UpdateDownloadPlan`:
    /// candidates in order, 3 attempts per URL with 1 s / 2 s / 4 s
    /// backoff, 60 s per-request timeout, `Range` resume from the partial
    /// file, size + SHA-256 verification of the final file (one full
    /// re-download on mismatch). Reports `download_started` first and
    /// `download_succeeded` / `download_failed` at the end. `progress`
    /// receives 0...1 (fraction of the manifest size on disk); it is called
    /// from a background context, so the caller must hop to the main actor
    /// before touching UI state.
    static func download(release: ReleaseEntry, progress: @escaping (Double) -> Void) async -> UpdateDownloadResult {
        // Service-level re-entrancy guard: at most one download runs at a
        // time, so concurrent calls cannot interleave appends to the same
        // partial file. (The AppModel-level guard stays too — this one
        // protects the service itself, whatever the caller.) A rejected
        // concurrent call reports nothing: no download started.
        guard await downloadGate.tryEnter() else {
            return .failure("已有下载在进行")
        }
        report(.downloadStarted)
        let result = await runDownload(release: release, progress: progress)
        await downloadGate.leave()
        switch result {
        case .success:
            report(.downloadSucceeded)
        case let .failure(reason):
            report(.downloadFailed(reason: reason))
        }
        return result
    }

    /// Serialises in-app downloads: the single download slot.
    private actor DownloadGate {
        private var inFlight = false
        /// Takes the slot, or false when one is already held.
        func tryEnter() -> Bool {
            guard !inFlight else { return false }
            inFlight = true
            return true
        }
        func leave() { inFlight = false }
    }

    private static let downloadGate = DownloadGate()

    private static func runDownload(release: ReleaseEntry, progress: @escaping (Double) -> Void) async -> UpdateDownloadResult {
        let plan = UpdateDownloadPlan(release: release)
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return .failure("无法访问缓存目录")
        }
        // Partial and finished files are named by version via the manifest
        // `file` (e.g. `Classday-v2.7.2.ipa` / `Classday-v2.7.2.ipa.partial`).
        let finalURL = caches.appendingPathComponent(release.file)
        let partialURL = caches.appendingPathComponent(release.file + ".partial")
        deleteStalePartials(in: caches, keeping: partialURL)

        // Reuse an already-downloaded file, but only after the same
        // size + hash verification a fresh download gets.
        if let data = try? Data(contentsOf: finalURL),
           data.count == release.size,
           UpdateDownloadPlan.sha256Matches(data: data, expected: release.sha256) {
            progress(1)
            return .success(finalURL)
        }
        try? fileManager.removeItem(at: finalURL)

        // One full re-download from scratch on a verification mismatch; a
        // second mismatch is a failure.
        for _ in 0...1 {
            if let reason = await fetchToPartial(plan: plan, partialURL: partialURL, expectedSize: release.size, progress: progress) {
                return .failure(reason)
            }
            // SHA-256 over the FINAL file, not the partial: the partial is
            // moved into place first, then the finished file is read back
            // and verified. A bad file is deleted, never offered to SideStore.
            try? fileManager.moveItem(at: partialURL, to: finalURL)
            guard let data = try? Data(contentsOf: finalURL), data.count == release.size else {
                // Size mismatch is a verification mismatch like a SHA
                // mismatch: delete and re-download once (the loop's second
                // iteration), rather than failing immediately.
                try? fileManager.removeItem(at: finalURL)
                continue
            }
            if UpdateDownloadPlan.sha256Matches(data: data, expected: release.sha256) {
                progress(1)
                return .success(finalURL)
            }
            try? fileManager.removeItem(at: finalURL)
        }
        return .failure("校验失败")
    }

    /// Tries every candidate URL in order until the partial file holds
    /// exactly `expectedSize` bytes. Returns `nil` on success, otherwise a
    /// human-readable failure reason (no user data). Exhausting one URL
    /// moves to the next; exhausting all URLs is a failure.
    private static func fetchToPartial(plan: UpdateDownloadPlan, partialURL: URL, expectedSize: Int, progress: @escaping (Double) -> Void) async -> String? {
        let fileManager = FileManager.default
        var lastReason = "下载失败"
        for url in plan.candidates {
            for attempt in 1...UpdateDownloadPlan.maxAttemptsPerURL {
                if Task.isCancelled { return "已取消" }
                // Oversized partials are corrupt: discard, do not resume.
                var partialSize = (try? fileManager.attributesOfItem(atPath: partialURL.path)[.size] as? Int) ?? 0
                if UpdateDownloadPlan.shouldDiscardPartial(partialSize: partialSize, expectedSize: expectedSize) {
                    try? fileManager.removeItem(at: partialURL)
                    partialSize = 0
                }
                let offset = UpdateDownloadPlan.resumeOffset(partialSize: partialSize, expectedSize: expectedSize)
                progress(Double(offset) / Double(max(expectedSize, 1)))
                if offset == expectedSize {
                    // The partial already holds the whole file (e.g. the
                    // app died between fetch and move): no request to send.
                    // `runDownload` moves it into place and verifies it.
                    return nil
                }
                do {
                    try await fetchChunk(url: url, offset: offset, partialURL: partialURL)
                    let newSize = (try? fileManager.attributesOfItem(atPath: partialURL.path)[.size] as? Int) ?? 0
                    progress(Double(newSize) / Double(max(expectedSize, 1)))
                    if newSize == expectedSize { return nil }
                    if newSize > expectedSize {
                        // Larger than the manifest size: corrupt, restart.
                        try? fileManager.removeItem(at: partialURL)
                        lastReason = "下载文件大小异常"
                    } else {
                        // Short body, not an error by itself: the next
                        // attempt resumes from the new offset.
                        lastReason = "下载不完整"
                    }
                } catch let error as URLError where error.code == .timedOut {
                    lastReason = "下载超时"
                } catch {
                    lastReason = "网络错误"
                }
                // Backoff 1 s / 2 s before the next attempt of this URL
                // (attempt 3's backoff, 4 s, is never slept: the URL is
                // exhausted and the loop moves to the next candidate).
                if attempt < UpdateDownloadPlan.maxAttemptsPerURL {
                    try? await Task.sleep(nanoseconds: UInt64(UpdateDownloadPlan.backoffSeconds(forAttempt: attempt)) * 1_000_000_000)
                }
            }
        }
        return lastReason
    }

    /// One ranged request against `url`, appending the body to `partialURL`.
    /// A 206 appends from `offset`; a 200 with `offset > 0` means the server
    /// ignored `Range`, so the partial is discarded and the file is fetched
    /// from scratch once, in the same attempt. A 200 with `offset == 0` is
    /// the ordinary full download.
    private static func fetchChunk(url: URL, offset: Int, partialURL: URL) async throws {
        let fileManager = FileManager.default
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(UpdateDownloadPlan.timeoutSeconds))
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 416 {
            // Range not satisfiable: the server is saying the partial
            // already holds the whole file. Nothing to append; the caller
            // re-reads the partial size and, when it equals the manifest
            // size, promotes + verifies it. (An incomplete partial that
            // gets a 416 falls through to "下载不完整" and retries.)
            return
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 200, offset > 0 {
            // Server ignored Range: restart from scratch once.
            try? fileManager.removeItem(at: partialURL)
            let fresh = URLRequest(url: url, timeoutInterval: TimeInterval(UpdateDownloadPlan.timeoutSeconds))
            let (fullData, freshResponse) = try await URLSession.shared.data(for: fresh)
            guard let freshHTTP = freshResponse as? HTTPURLResponse, (200...299).contains(freshHTTP.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try fullData.write(to: partialURL, options: .atomic)
            return
        }
        if offset == 0 {
            try data.write(to: partialURL, options: .atomic)
        } else {
            guard let handle = try? FileHandle(forWritingTo: partialURL) else {
                throw URLError(.cannotWriteToFile)
            }
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }

    /// Deletes stale partial files in `directory`: partials of other
    /// versions, and the current partial when it is older than 7 days.
    /// Scoped to this feature's naming (`Classday-v*.ipa.partial`):
    /// other tools' `.partial` files in caches are not ours to delete.
    private static func deleteStalePartials(in directory: URL, keeping currentPartial: URL) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for item in items where item.lastPathComponent.hasPrefix("Classday-v")
            && item.lastPathComponent.hasSuffix(".ipa.partial") {
            if item == currentPartial {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? fileManager.removeItem(at: item)
                }
                continue
            }
            try? fileManager.removeItem(at: item)
        }
    }

    /// Manifest path. Returns `nil` on ANY failure (network, timeout, bad
    /// HTTP body, parse, validation) so the caller falls back to the API
    /// path. The `nil` is the fallback trigger, not an error to surface.
    private static func checkManifest(currentVersion: String) async -> CheckResult? {
        do {
            var request = URLRequest(url: manifestURL, timeoutInterval: manifestTimeout)
            let (data, response) = try await URLSession.shared.data(for: request)
            // A non-2xx response (e.g. a 404 or a GitHub error page) is not
            // a manifest: fall back to the API path instead of decoding
            // an error body as JSON.
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            switch decision(manifest: manifest, current: currentVersion) {
            case .upToDate:
                return CheckResult(decision: .upToDate, note: "已是最新版", downloadURL: nil)
            case let .updateAvailable(release, mandatory: mandatory):
                // The mandatory flag changes nothing in the row in this task;
                // the blocking alert is Task 6. The row still shows the new
                // version with the manifest download link.
                return CheckResult(
                    decision: .updateAvailable(release: release, mandatory: mandatory),
                    note: "新版 \(release.version)",
                    downloadURL: release.downloadURL
                )
            case let .belowMinimumSupported(release):
                // Same row as an ordinary update: a newer release exists.
                // The "no longer supported" blocking alert is Task 6.
                return CheckResult(
                    decision: .belowMinimumSupported(release: release),
                    note: "新版 \(release.version)",
                    downloadURL: release.downloadURL
                )
            }
        } catch {
            return nil
        }
    }

    /// The pre-Task-5 GitHub Releases API path, unchanged: same request,
    /// same compare, same fixed-name raw IPA URL. Runs whenever the manifest
    /// path fails, and keeps working when `latest.json` is down or malformed.
    private static func checkGitHubReleasesAPI(currentVersion: String) async -> CheckResult {
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/yuanyeye0210-debug/classday-ios/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            if version(latest, isNewerThan: currentVersion) {
                // Release assets can't be attached through the API token
                // channel (uploads host), so the IPAs live in the public
                // classday-releases archive repo under predictable names.
                return CheckResult(
                    decision: nil,
                    note: "新版 \(latest)",
                    downloadURL: URL(string: "https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/Classday-v\(latest).ipa")
                )
            }
            return CheckResult(decision: nil, note: "已是最新版", downloadURL: nil)
        } catch {
            return CheckResult(decision: nil, note: "检查失败", downloadURL: nil)
        }
    }

    /// Numeric dot-separated version compare for the GitHub Releases API
    /// fallback path. Delegates to Core's `compareVersions` — the single
    /// compare in the codebase — so the fallback and the manifest
    /// decision can never drift apart. (Each segment as an integer, so
    /// 2.7.10 > 2.7.9; missing segments count as 0; a non-numeric segment
    /// counts as 0.)
    private static func version(_ a: String, isNewerThan b: String) -> Bool {
        compareVersions(a, b) == .orderedDescending
    }
}

private struct GitHubRelease: Decodable {
    let tag_name: String
}
