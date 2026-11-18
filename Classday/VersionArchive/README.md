# VersionArchive

This is the only directory version snapshots may modify or delete.

V1 is `1.0.0` and has no `previous/` snapshot. Do not invent one.

The version-update command is `Tools/bump-version.sh X.Y.Z`. It archives the last commit into `previous/` before it writes the new version, then removes older version directories here. Ordinary git commits are not archived.

The marker file `.classday-backup-root` must contain exactly `classday-version-archive-v1` followed by a newline. A snapshot also contains `VERSION` and `.classday-snapshot-version` for the replaced version. This folder must not contain another `VersionArchive`.
