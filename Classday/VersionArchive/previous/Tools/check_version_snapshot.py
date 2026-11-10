#!/usr/bin/env python3
"""Fail when a Classday version change did not archive the committed version it replaced.

Scope: marketing-version bumps of Classday/VERSION. Ordinary commits are not required
to create a snapshot. Deletes are not performed here; this script only reads git and
VersionArchive.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
STAMP_NAME = ".classday-snapshot-version"


def repo_root_from_classday() -> Path:
    return Path(__file__).resolve().parents[2]


def run_git(repo: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def git_show(repo: Path, rev: str, path: str) -> str | None:
    result = run_git(repo, ["show", f"{rev}:{path}"])
    if result.returncode != 0:
        return None
    return result.stdout


def parse_version(text: str | None) -> str | None:
    if text is None:
        return None
    line = text.strip().splitlines()[0].strip() if text.strip() else ""
    if not VERSION_RE.fullmatch(line):
        return None
    return line


def marketing_versions(classday: Path) -> dict[str, str]:
    version = parse_version((classday / "VERSION").read_text(encoding="utf-8"))
    if version is None:
        raise SystemExit("Classday/VERSION is missing or not X.Y.Z")
    yml = (classday / "project.yml").read_text(encoding="utf-8")
    yml_match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', yml)
    pbx = (classday / "Classday.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    pbx_values = set(re.findall(r"MARKETING_VERSION = ([^;]+);", pbx))
    pbx_values = {value.strip().strip('"') for value in pbx_values}
    found = {"VERSION": version}
    if yml_match:
        found["project.yml"] = yml_match.group(1)
    found["pbxproj"] = ",".join(sorted(pbx_values))
    problems = []
    if found.get("project.yml") != version:
        problems.append(f"project.yml MARKETING_VERSION is {found.get('project.yml')}, VERSION is {version}")
    if pbx_values != {version}:
        problems.append(f"project.pbxproj MARKETING_VERSION values are {sorted(pbx_values)}, VERSION is {version}")
    if problems:
        raise SystemExit("version files disagree:\n" + "\n".join(problems))
    return found


def archive_directories(archive: Path) -> list[Path]:
    return sorted(
        child for child in archive.iterdir()
        if child.is_dir() and not child.is_symlink() and not child.name.startswith(".")
    )


def require_no_previous(classday: Path) -> None:
    previous = classday / "VersionArchive" / "previous"
    if previous.exists():
        raise SystemExit(
            "This change introduces Classday or does not replace a committed version, "
            "but VersionArchive/previous exists. Do not fabricate a previous snapshot."
        )


def require_snapshot(classday: Path, expected: str, current: str) -> None:
    archive = classday / "VersionArchive"
    previous = archive / "previous"
    if not previous.is_dir():
        raise SystemExit(
            f"Version changed from {expected} to {current}, but VersionArchive/previous is missing. "
            "Use Tools/bump-version.sh so the committed version is archived before the number changes."
        )
    stamp_path = previous / STAMP_NAME
    if not stamp_path.is_file():
        raise SystemExit("VersionArchive/previous has no .classday-snapshot-version stamp.")
    stamp = parse_version(stamp_path.read_text(encoding="utf-8"))
    captured = parse_version((previous / "VERSION").read_text(encoding="utf-8"))
    if stamp != expected or captured != expected:
        raise SystemExit(
            f"Snapshot records {stamp!r} (VERSION file {captured!r}); the replaced commit is {expected}. "
            "The archive must be the old committed version, not the version being written."
        )
    if stamp == current:
        raise SystemExit("Snapshot version matches the new version. The old tree was not archived.")
    if (previous / "VersionArchive").exists():
        raise SystemExit("VersionArchive/previous contains a nested VersionArchive.")
    names = [path.name for path in archive_directories(archive)]
    if names != ["previous"]:
        raise SystemExit(f"VersionArchive may contain only previous/, found directories: {names or '(none)'}")


def check(repo: Path, base: str | None) -> None:
    classday = repo / "Classday"
    if not (classday / "VERSION").is_file():
        return
    versions = marketing_versions(classday)
    current = versions["VERSION"]
    if base is None:
        previous = classday / "VersionArchive" / "previous"
        if previous.exists():
            stamp = parse_version((previous / STAMP_NAME).read_text(encoding="utf-8"))
            if stamp == current:
                raise SystemExit("Working snapshot is stamped with the current version.")
            if (previous / "VersionArchive").exists():
                raise SystemExit("Nested VersionArchive inside previous/.")
        return

    commits = run_git(repo, ["log", "--format=%H", f"{base}..HEAD", "--", "Classday/VERSION"])
    if commits.returncode != 0:
        raise SystemExit(commits.stderr.strip() or "git log failed")
    hashes = [line for line in commits.stdout.splitlines() if line.strip()]
    if not hashes:
        base_version = parse_version(git_show(repo, base, "Classday/VERSION"))
        if base_version is None:
            require_no_previous(classday)
        elif base_version != current:
            raise SystemExit(f"VERSION is {current} but {base} is {base_version} and no bump commit was found.")
        else:
            previous = classday / "VersionArchive" / "previous"
            if previous.exists():
                require_snapshot(classday, parse_version((previous / STAMP_NAME).read_text(encoding="utf-8")) or "", current)
                if parse_version((previous / STAMP_NAME).read_text(encoding="utf-8")) == current:
                    raise SystemExit("Unchanged version has a snapshot of itself.")
        return

    latest = hashes[0]
    parent = run_git(repo, ["rev-parse", f"{latest}^"])
    if parent.returncode != 0:
        require_no_previous(classday)
        return
    parent_version = parse_version(git_show(repo, parent.stdout.strip(), "Classday/VERSION"))
    if parent_version is None:
        require_no_previous(classday)
        return
    if parent_version == current:
        raise SystemExit(f"Latest VERSION commit does not change {current}.")
    require_snapshot(classday, parent_version, current)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as raw:
        repo = Path(raw)
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "snapshot-test@example.com"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Snapshot Test"], cwd=repo, check=True)

        def commit(message: str) -> str:
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-q", "-m", message], cwd=repo, check=True)
            return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()

        def write_classday(version: str, payload: str, previous: str | None) -> None:
            classday = repo / "Classday"
            (classday / "Classday.xcodeproj").mkdir(parents=True, exist_ok=True)
            archive = classday / "VersionArchive"
            if archive.exists():
                shutil.rmtree(archive)
            archive.mkdir()
            (classday / "VERSION").write_text(version + "\n", encoding="utf-8")
            (classday / "project.yml").write_text(f'MARKETING_VERSION: "{version}"\n', encoding="utf-8")
            (classday / "Classday.xcodeproj" / "project.pbxproj").write_text(
                f"MARKETING_VERSION = {version};\n", encoding="utf-8"
            )
            (classday / "payload.txt").write_text(payload, encoding="utf-8")
            (archive / ".classday-backup-root").write_text("classday-version-archive-v1\n", encoding="utf-8")
            previous_dir = archive / "previous"
            if previous is None:
                pass
            else:
                if previous_dir.exists():
                    subprocess.run(["rm", "-rf", str(previous_dir)], check=True)
                previous_dir.mkdir()
                (previous_dir / "VERSION").write_text(previous + "\n", encoding="utf-8")
                (previous_dir / STAMP_NAME).write_text(previous + "\n", encoding="utf-8")
                (previous_dir / "payload.txt").write_text(f"snapshot-{previous}", encoding="utf-8")

        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "empty"], cwd=repo, check=True)
        base_empty = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
        write_classday("1.0.0", "alpha", None)
        v1 = commit("add classday 1.0.0")
        check(repo, base_empty)

        write_classday("1.1.0", "beta", None)
        commit("bump without snapshot")
        try:
            check(repo, v1)
        except SystemExit:
            pass
        else:
            raise SystemExit("self-test: skipped snapshot was accepted")
        subprocess.run(["git", "reset", "-q", "--hard", v1], cwd=repo, check=True)

        write_classday("1.1.0", "beta", "1.0.0")
        v11 = commit("bump 1.1.0 with snapshot of 1.0.0")
        check(repo, v1)

        write_classday("1.2.0", "gamma", "1.1.0")
        (repo / "Classday" / "VersionArchive" / "older").mkdir()
        commit("bump keeping ancient archive")
        try:
            check(repo, v11)
        except SystemExit:
            pass
        else:
            raise SystemExit("self-test: older archive directory was accepted")
        subprocess.run(["git", "reset", "-q", "--hard", v11], cwd=repo, check=True)

        write_classday("1.2.0", "gamma", "1.1.0")
        commit("bump 1.2.0 with immediate previous")
        check(repo, v1)
        check(repo, v11)
        nested = repo / "Classday" / "VersionArchive" / "previous" / "VersionArchive"
        nested.mkdir()
        try:
            check(repo, v11)
        except SystemExit:
            pass
        else:
            raise SystemExit("self-test: nested archive was accepted")
    print("version snapshot check self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="git revision to compare against, such as origin/main")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    repo = repo_root_from_classday()
    try:
        check(repo, args.base)
    except SystemExit as error:
        if error.code not in (None, 0) and str(error):
            print(error, file=sys.stderr)
        elif str(error):
            print(error, file=sys.stderr)
        return 1
    print("version snapshot check passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as error:
        if error.code in (None, 0):
            raise
        if str(error):
            print(error, file=sys.stderr)
        sys.exit(1 if error.code is None else int(error.code) if isinstance(error.code, int) else 1)
