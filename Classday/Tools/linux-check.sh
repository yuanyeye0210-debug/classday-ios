#!/usr/bin/env bash
# Linux/macOS checks that do not need Xcode. Swift must be on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${1:-$ROOT/Docs}"
mkdir -p "$LOG_DIR"
python3 "$ROOT/Tools/check_project.py" | tee "$LOG_DIR/project-check.log"
(
  cd "$ROOT/ClassdayCore"
  swift test --jobs 4
) 2>&1 | tee "$LOG_DIR/swift-test.log"
echo "logs: $LOG_DIR/project-check.log $LOG_DIR/swift-test.log"
