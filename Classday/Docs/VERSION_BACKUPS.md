# Version backups

Automatic snapshots happen only when the marketing version changes, and only through one command:

```bash
Classday/Tools/bump-version.sh 1.1.0
```

That command:

1. Reads `Classday/VERSION` from the last commit (`HEAD`). That committed tree is the old version. `VERSION` is the only marketing-version source of truth. `Classday/BUILD` is the only build-number source of truth (`CFBundleVersion` / `CURRENT_PROJECT_VERSION`). `project.yml` and `project.pbxproj` are generated from those two files.
2. Copies that tree into `VersionArchive/previous`, including `VERSION` and `.classday-snapshot-version`. It does not copy the working tree, so edits that are not committed yet are not what gets archived.
3. Deletes every other directory inside `VersionArchive` (the previous snapshot and any older folder such as `older/` or `v1/`).
4. Writes the new version to `Classday/VERSION`, writes `BUILD` as one higher than the committed build, then regenerates `project.pbxproj` and syncs `project.yml`. A committed tree with no `BUILD` file counts as build 1, which is the number every release used before the file existed, so the next release becomes build 2.

`VersionArchive/` is the only directory the command may delete from. The marker file `.classday-backup-root` must still say `classday-version-archive-v1`. The archive may hold `previous/`, the marker, this README's sibling `README.md`, and ordinary files. It must not contain a nested `VersionArchive`. Git history is not rewritten. Nothing is merged or published.

## What is not automatic

A normal commit, a hand edit, or `git commit -a` does not create a snapshot. There is no scheduled job. `Tools/rotate-backup.sh` is not the version workflow: without `--low-level` it refuses, because copying the working tree can archive a version that was already edited.

If `VERSION`, `BUILD`, `project.yml`, or `project.pbxproj` already differ from `HEAD`, `bump-version.sh` stops. Restore or commit those files first, then run the bump. The snapshot is still the last commit, and the command is what changes the version number. Do not hand-edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`.

V1 is `1.0.0` and has no `previous/` directory. Do not create one by hand.

## CI

`.github/workflows/classday-version-snapshot.yml` runs on pull requests:

```bash
python3 Classday/Tools/check_version_snapshot.py --base origin/<base>
```

It looks at the newest commit in the pull request that changes `Classday/VERSION`.

- If that file did not exist in the parent commit and `project.pbxproj` has no marketing version either, this is the first import. `previous/` must be absent.
- If the parent commit had no `VERSION` file but `project.pbxproj` already carried the same marketing version, restoring the file is not a bump and does not require a new snapshot.
- If the parent commit had a different version (from `VERSION`, or from `project.pbxproj` when `VERSION` was absent), `previous/.classday-snapshot-version` and `previous/VERSION` must both be that parent version, not the new number. `BUILD` must be greater than the parent build when the parent had a `BUILD` file. Any other directory in `VersionArchive` fails the check.
- Two bumps in one branch are valid: the archive keeps the immediate parent version, and the older snapshot is gone.
- A pull request that does not change `Classday/VERSION` does not need a new snapshot.
- Deleting `Classday/VERSION` while the Xcode project remains fails the check.

The snapshot checked in today is still `1.0.1`, the last tree `bump-version.sh` archived. Later releases edited `project.pbxproj` directly and did not replace it. The next bump archives the committed `2.7.1` tree. Do not invent a `2.7.0` snapshot by hand.

`python3 Classday/Tools/check_version_snapshot.py --self-test` builds a temporary git repository and covers a skipped snapshot, a nested archive, an older directory, and two successive bumps.
