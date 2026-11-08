# VersionArchive

This directory is the only tree the Classday version-backup tool may modify.

V1 is the first version, so there is no `previous/` snapshot. Do not invent one.

When a later version replaces this tree, run `Tools/rotate-backup.sh` first. The tool:

- copies the current `Classday/` tree into `VersionArchive/previous`, excluding this archive, `.git`, build products, and symlinks
- deletes other directories inside `VersionArchive` (older version folders)
- leaves `previous/`, this README, the marker file, and other ordinary files in place
- refuses to run if the directory is not named `VersionArchive` or the marker file is missing or wrong
- never rewrites git history and never deletes paths outside this directory

The marker file `.classday-backup-root` must contain exactly `classday-version-archive-v1` followed by a single newline.
