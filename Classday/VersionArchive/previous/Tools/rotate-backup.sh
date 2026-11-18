#!/usr/bin/env bash
# Low-level copy of a directory into VersionArchive/previous.
# Version updates must use bump-version.sh, which snapshots the last commit first.
# This script copies the directory you pass, so a tree that is already edited is the wrong source.
set -euo pipefail
if [[ "${1:-}" != "--low-level" ]]; then
  echo "Version updates use Tools/bump-version.sh X.Y.Z." >&2
  echo "That command archives the last commit, then changes the version." >&2
  echo "Pass --low-level only to copy an explicit directory into the managed archive." >&2
  exit 2
fi
shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT}"
ARCHIVE="$ROOT/VersionArchive"
cd "$ROOT/ClassdayCore"
swift run --disable-sandbox classday-backup rotate --source "$SOURCE" --archive "$ARCHIVE"
