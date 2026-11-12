#!/usr/bin/env bash
# One version-update command.
# 1. Snapshot the last commit of Classday (the version number still on HEAD).
# 2. Only then write the new marketing version and the next build number.
# Ordinary commits are not archived. This does not rewrite git history or publish.
# VERSION is the marketing version. BUILD is CFBundleVersion / CURRENT_PROJECT_VERSION.
# project.yml and project.pbxproj are rewritten from those two files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
NEW="${1:-}"

if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: Tools/bump-version.sh X.Y.Z" >&2
  echo "Snapshots HEAD of Classday into VersionArchive/previous, then sets VERSION to X.Y.Z and increments BUILD." >&2
  exit 2
fi

cd "$REPO"
git rev-parse --is-inside-work-tree >/dev/null
if ! git cat-file -e HEAD:Classday/VERSION 2>/dev/null; then
  echo "HEAD has no Classday/VERSION, so there is no committed version to archive." >&2
  exit 3
fi

version_paths=(
  Classday/VERSION
  Classday/BUILD
  Classday/project.yml
  Classday/Classday.xcodeproj/project.pbxproj
  Classday/Tools/generate_xcodeproj.py
)
if ! git diff --quiet HEAD -- "${version_paths[@]}"; then
  echo "Version files differ from HEAD. Restore or commit them before bumping." >&2
  echo "The snapshot is the last commit, and this command is what changes the version." >&2
  exit 3
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git archive --format=tar HEAD:Classday | tar -x -C "$TMP"

cd "$ROOT/ClassdayCore"
swift run --disable-sandbox classday-backup bump \
  --committed "$TMP" \
  --working "$ROOT" \
  --to "$NEW"
python3 "$ROOT/Tools/generate_xcodeproj.py"
echo "bumped to $NEW (build $(tr -d '[:space:]' < "$ROOT/BUILD")); previous snapshot is the committed tree from HEAD"
