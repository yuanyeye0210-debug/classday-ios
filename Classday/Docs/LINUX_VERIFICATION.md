# Linux verification

Recorded on 8 November 2026 with Swift 6.3 (swift-6.3-RELEASE, x86_64-unknown-linux-gnu).

Xcode is not installed in this environment. `xcodebuild` was not run. No simulator screenshots were captured. No IPA was produced. The app icon PNG is a source-drawn asset, not a simulator capture.

## Commands

```bash
python3 Classday/Tools/check_project.py
cd Classday/ClassdayCore && swift test
swift run classday-backup inspect --source <temp> --archive <temp>/VersionArchive
```

## Results

`project check passed (12 app sources, 2 widget sources)`

`swift test`: 18 tests, 0 failures.

- BackupRotationTests: 3 passed
- ScheduleTests: 6 passed
- StoreTests: 5 passed
- WidgetNotificationTests: 4 passed

`classday-backup inspect` on a temporary archive printed a plan and did not create `previous/`. The repository `VersionArchive` still contains only `README.md` and `.classday-backup-root`.

Full logs from this run are stored with the task artifacts: `swift-test.log`, `project-check.log`, `backup-inspect.log`, `swift-version.txt`, and `classday-v1-source.tar.gz`.
