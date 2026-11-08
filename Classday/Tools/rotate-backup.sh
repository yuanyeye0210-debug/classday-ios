#!/usr/bin/env bash
# Snapshot the current Classday tree into VersionArchive/previous.
# Refuses to touch anything outside that directory. Do not run this for the initial V1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT}"
ARCHIVE="$ROOT/VersionArchive"
cd "$ROOT/ClassdayCore"
swift run --disable-sandbox classday-backup rotate --source "$SOURCE" --archive "$ARCHIVE"
