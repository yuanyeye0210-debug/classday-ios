# Version backups

Automatic snapshots happen only when the marketing version changes, and only through one command:

```bash
Classday/Tools/bump-version.sh 1.1.0
```

That command:

1. Reads `Classday/VERSION` from the last commit (`HEAD`). That committed tree is the old version.
2. Copies that tree into `VersionArchive/previous`, including `VERSION` and `.classday-snapshot-version`. It does not copy the working tree, so edits that are not committed yet are not what gets archived.
3. Deletes every other directory inside `VersionArchive` (the previous snapshot and any older folder such as `older/` or `v1/`).
4. Writes the new version to `Classday/VERSION`, then regenerates `project.pbxproj` and syncs `project.yml`.

`VersionArchive/` is the only directory the command may delete from. The marker file `.classday-backup-root` must still say `classday-version-archive-v1`. The archive may hold `previous/`, the marker, this README's sibling `README.md`, and ordinary files. It must not contain a nested `VersionArchive`. Git history is not rewritten. Nothing is merged or published.

## What is not automatic

A normal commit, a hand edit, or `git commit -a` does not create a snapshot. There is no scheduled job. `Tools/rotate-backup.sh` is not the version workflow: without `--low-level` it refuses, because copying the working tree can archive a version that was already edited.

If `VERSION`, `project.yml`, or `project.pbxproj` already differ from `HEAD`, `bump-version.sh` stops. Restore or commit those files first, then run the bump. The snapshot is still the last commit, and the command is what changes the version number.

V1 is `1.0.0` and has no `previous/` directory. Do not create one by hand.

## CI

`.github/workflows/classday-version-snapshot.yml` runs on pull requests:

```bash
python3 Classday/Tools/check_version_snapshot.py --base origin/<base>
```

It looks at the newest commit in the pull request that changes `Classday/VERSION`.

- If that file did not exist in the parent commit, this is the first import. `previous/` must be absent.
- If the parent commit had a version, `previous/.classday-snapshot-version` and `previous/VERSION` must both be that parent version, not the new number. Any other directory in `VersionArchive` fails the check.
- Two bumps in one branch are valid: the archive keeps the immediate parent version, and the older snapshot is gone.
- A pull request that does not change `Classday/VERSION` does not need a new snapshot.

`python3 Classday/Tools/check_version_snapshot.py --self-test` builds a temporary git repository and covers a skipped snapshot, a nested archive, an older directory, and two successive bumps.
