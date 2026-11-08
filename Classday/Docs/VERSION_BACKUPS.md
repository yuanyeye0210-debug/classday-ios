# Version backups

`Classday/VersionArchive` is the only managed backup folder.

The tool is `classday-backup` in the `ClassdayCore` package, wrapped by `Tools/rotate-backup.sh`.

```bash
# show what would be copied and which archive directories would be removed
cd Classday/ClassdayCore
swift run classday-backup inspect --source .. --archive ../VersionArchive

# when you are about to replace the current tree with a newer version
../Tools/rotate-backup.sh
```

Rules:

- The archive directory must be named `VersionArchive`.
- It must contain `.classday-backup-root` whose contents are exactly `classday-version-archive-v1` plus a newline.
- The source must not be inside the archive. The archive may sit inside the source; it is excluded from the copy.
- Symlinks are not followed and are not copied. A symlink inside the archive is unlinked, not traversed.
- After a rotation, the archive holds `previous/` (the snapshot just taken), the marker, `README.md`, and any ordinary files. Other directories, including an older `previous/` and folders such as `v1` or `older`, are deleted.
- Nothing outside the archive is deleted. Git history is not rewritten. The script is not a scheduled job.
- Build directories (`.build`, `.swiftpm`, `DerivedData`, `xcuserdata`) and `.git` are not copied.

V1 has no `previous/` directory. Do not create one by hand to imitate an older release.
