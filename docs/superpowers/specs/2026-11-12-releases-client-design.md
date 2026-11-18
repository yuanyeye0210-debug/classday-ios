# classday-releases batch 3 — client-side design (classday-ios)

> Status: **approved by Eric in chat, 2026-11-12 14:14** ("设计通过，开分支实施").
> Branch: `feat/releases-client`, from main `676f6ce` (PR #9 merged).
> Companion plan: `docs/superpowers/plans/2026-11-12-releases-client.md`.
> Repo-side contract: `classday-releases` main `e6daa0a` (batches 1–3 merged).

## Background (verified, not assumed)

- Live `latest.json` (read 2026-11-12 14:05): `schema_version` 1, `updated_at`
  2026-11-12T09:34:21Z; `channels.ios.latest` 2.7.1, `mandatory` false,
  `min_supported_version` 2.7.0, `previous` 2.7.0; each release carries `file`,
  `size`, `sha256`, `download_url`, `published_at`. `channels.android` is null.
  No release currently carries `mirrors`.
- Current client (`SettingsView.checkForUpdate`, lines 726–742): GETs
  `api.github.com/repos/yuanyeye0210-debug/classday-ios/releases/latest`,
  decodes `tag_name`, strips a `v` prefix, compares against
  `CFBundleShortVersionString` with `SettingsView.version(_:isNewerThan:)`
  (numeric dot-separated compare). If newer, shows "新版 \(latest)" and a
  `Link` to `raw.githubusercontent.com/.../classday-releases/main/Classday-v\(latest).ipa`
  (line 333–335). No manifest read, no checksum, no retry/resume, no reporting.
- `classday-releases/README.md` (batch 3) defines the client contract: manifest
  schema v1, per-release optional `mirrors` (client tries `download_url` first,
  then mirrors in order), and the reporting payload (`app_version`, `platform`,
  `build`, `event`, `error?`, `timestamp` UTC ISO `YYYY-MM-DDTHH:MM:SSZ`).
  Events: `update_check`, `download_started`, `download_succeeded`,
  `download_failed`, `installed`. **No collector endpoint exists yet** — the
  client implements the send logic per this field contract; the endpoint is
  wired up when it is decided. Reporting must never block the client.
- No existing download/resume code anywhere in the app; no `CFBundleVersion`
  read anywhere (build number is read fresh for reporting). `URLSession` is
  used directly in a few places (FenixAuth, SettingsView); there is no shared
  download helper.

## 1. Update check reads latest.json

- New Core model `UpdateManifest` (Codable): `schema_version`, `updated_at`,
  `channels.ios` (`latest`, `previous`, `mandatory`, `min_supported_version`,
  `releases[]` with `file`, `size`, `sha256`, `download_url`, `published_at`,
  optional `mirrors: [String]`). Validation: `schema_version` must be 1,
  `channels.ios` must be non-null, `latest` must name a release present in
  `releases[]`. Any violation = treat as "manifest unusable" (see fallback).
- Fetch: GET
  `https://raw.githubusercontent.com/yuanyeye0210-debug/classday-releases/main/latest.json`,
  15 s timeout, one attempt (no retry — the fallback covers failure).
- Fallback: on any manifest failure (network, timeout, parse, validation),
  use the existing GitHub Releases API path **unchanged** (same request, same
  compare, same fixed-name raw URL). The fallback must keep working when
  `latest.json` is down or malformed.
- Decision (pure, in Core): compare `latest` against the current
  `CFBundleShortVersionString`. Reuse the existing compare — check
  `ClassdayCore/VersionBump.swift` first; if it already has a SemVer compare,
  use it and remove the duplication from `SettingsView.version(_:isNewerThan:)`
  only if that is a safe, review-approved cleanup, otherwise leave
  `SettingsView`'s helper alone.
- `mandatory == true`: show a non-dismissable alert with a single
  "下载更新" button (no "以后再说"). The update row still shows the new version.
- Current version below `min_supported_version`: same blocking alert, copy
  states the current version is no longer supported.
- Ordinary update: the row keeps its current look ("新版 X" + link) and gains
  an in-app download action (see §2).
- Auto-check (new behaviour, approved): at most once per day, silent, on app
  launch; it only surfaces UI when an update is found (or a mandatory /
  below-minimum condition applies). Manual tap on "检查更新" always checks
  immediately. Last-check date is persisted (UserDefaults); the check never
  blocks launch and never shows "已是最新版" on its own.

## 2. In-app download: retry + resume + verify

- Candidate order (pure, in Core as `UpdateDownloadPlan`): the release's
  `download_url`, then its `mirrors` in order. Exhausting one URL moves to the
  next; exhausting all URLs = failure.
- Per URL: at most 3 attempts, backoff 1 s → 2 s → 4 s, per-request timeout
  60 s. A retry resumes from the bytes already on disk (see below), it does
  not restart the file.
- Resume: HTTP `Range: bytes=<received>-` against a partial file in the caches
  directory, named by version (e.g. `Classday-v2.7.2.ipa.partial`). If the
  server answers 200 instead of 206 (no Range support), discard the partial
  file and download from scratch once. Stale partials (different version, or
  older than 7 days) are deleted before starting.
- Verify before handing the file to the user: downloaded size must equal the
  manifest `size`, and SHA-256 (CryptoKit, streamed in chunks) must equal the
  manifest `sha256`. On mismatch: delete, re-download once from scratch; a
  second mismatch = failure. A bad file is never offered to SideStore.
- Success: present a share sheet with the finished `.ipa` so the user taps
  "在 SideStore 中打开". The row shows download progress while downloading.
- Total failure: fall back to the current behaviour — open the manifest
  `download_url` in Safari via the existing `Link`. The user always keeps a
  path to the update.
- Networking shape: manual `Range` data tasks over `URLSession` (not
  `URLSessionDownloadTask` with resume data) so resume offset, progress and
  per-URL retry are explicit and unit-testable. Confirm this choice against
  the codebase during Task 6; if the app already has a download helper that
  fits, use it instead and record why.

## 3. Version-distribution reporting

- Payload (pure, in Core as `UpdateReport`): exactly the README fields —
  `app_version` = `CFBundleShortVersionString`, `platform` = `"ios"`,
  `build` = `CFBundleVersion` (fallback `"0"`), `event`, `error` (only for
  `download_failed`, human-readable reason, no user data), `timestamp` = UTC
  `YYYY-MM-DDTHH:MM:SSZ`. No device identifier, no user data, ever.
- Events: `update_check` (one per completed check, success or failure),
  `download_started`, `download_succeeded`, `download_failed`,
  `installed` (detected on launch: stored last-reported version differs from
  the current version — the only reliable signal that the new version was
  installed; persist the last-reported version in UserDefaults).
- Transport: the sender (thin, App layer) POSTs JSON to a collector endpoint.
  **There is no collector yet, so the endpoint constant is empty and sending
  is disabled by default.** The full pipeline (event construction, gating,
  fire-and-forget dispatch) is implemented and tested; enabling it later is
  filling in one constant. Until then no reporting request is ever made.
- Hard rule: reporting is fire-and-forget, off the critical path. A send
  failure is swallowed silently — no retry, no alert, no blocking. Reporting
  must not delay the check result, the download, or app launch.

## Architecture

- Pure logic in `ClassdayCore` (covered by `swift test`, which CI runs):
  `UpdateManifest.swift` (decode + validate + latest-release selection),
  `UpdateDownloadPlan.swift` (candidate order, retry policy, resume offset,
  size/SHA-256 verification helpers), `UpdateReport.swift` (payload building,
  event enum, enabled gate, installed detection). Version compare reuses
  `VersionBump.swift` if it has one.
- Thin App layer: manifest fetch + fallback (`SettingsView` / a small
  `UpdateService`), `URLSession` download with progress, CryptoKit streaming
  hash, share sheet, alerts, daily auto-check trigger.
- No version bump in this batch (`Classday/VERSION` stays `2.7.1`). No
  workflow changes. No new user-visible copy except the update alert/progress
  strings (Chinese, matching the existing "新版 / 已是最新版 / 检查失败"
  wording).

## Android sync

- The shared contract stays platform-agnostic: manifest schema v1, report
  payload fields and event names, candidate order (download_url → mirrors),
  retry policy (3 attempts, 1 s/2 s/4 s backoff), resume via `Range`, and
  SHA-256 verification. Only the transport is iOS-specific (`URLSession`,
  CryptoKit, SwiftUI, UserDefaults). Record any contract change in this doc
  and in `classday-releases/README.md` if the README's client contract needs
  it.

## Testing

- Core unit tests (`swift test`, CI): manifest decoding of the real live
  `latest.json` shape (kept as a fixture), schema_version mismatch, ios null,
  mirrors absent/present, latest-not-in-releases; version-compare edge cases;
  candidate ordering; resume-offset math; SHA-256 of a known file and of a
  tampered file (must fail); report payload fields and timestamp format;
  installed detection; sender disabled when no endpoint is configured.
- Network behaviour (retry, resume, 200-instead-of-206, timeout) is tested
  with a stub `URLProtocol` serving byte ranges — no real network in CI.
- App-layer wiring (fetch, fallback, alerts, share sheet, auto-check) is
  verified by `xcodebuild` build success + code review; it has no unit-test
  target in CI.
