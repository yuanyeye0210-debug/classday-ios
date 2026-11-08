# Linux verification

Recorded on 8 November 2026 with Swift 6.3 (swift-6.3-RELEASE, x86_64-unknown-linux-gnu).

Xcode is not installed here. `xcodebuild` was not run. No simulator screenshots were captured. No IPA was produced.

## Commands

```bash
python3 Classday/Tools/check_project.py
python3 Classday/Tools/check_version_snapshot.py --self-test
cd Classday/ClassdayCore && swift test
```

## Results

`project check passed (12 app sources, 2 widget sources)`

`version snapshot check self-test passed`

`swift test`: 21 tests, 0 failures.

- BackupRotationTests: 3 passed
- ScheduleTests: 6 passed
- StoreTests: 5 passed
- VersionBumpTests: 3 passed, including two successive bumps that keep only the immediate previous snapshot
- WidgetNotificationTests: 4 passed

`VersionArchive/` in this tree still has only `README.md` and `.classday-backup-root`. V1 does not contain `previous/`.

Full logs from this run are stored with the task artifacts: `swift-test.log`, `project-check.log`, `version-snapshot-check.log`, and `classday-v1-source.tar.gz`.
