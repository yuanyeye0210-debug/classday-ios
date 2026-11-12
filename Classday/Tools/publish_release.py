#!/usr/bin/env python3
"""Build the SideStore/AltStore source for classday-releases.

The GitHub Actions workflow clones that repo, runs `update`, commits, and pushes.
This script does not clone, commit, push, or read tokens.

`apps.json` lists only the current IPA and the immediately previous one.
SideStore treats the first version in the array as the latest release, so the
newer version is written first. `version` and `buildVersion` are copied from
the IPA's Info.plist so they match CFBundleShortVersionString and CFBundleVersion.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
import tempfile
import zipfile
from pathlib import Path

SOURCE_NAME = "课曜 / Heptara"
SOURCE_ID = "com.classday.source"
BUNDLE_ID = "com.classday.app"
APP_NAME = "课曜"
DEVELOPER_NAME = "课曜"
REPOSITORY = "yuanyeye0210-debug/classday-releases"
SOURCE_URL = f"https://raw.githubusercontent.com/{REPOSITORY}/main/apps.json"
DOWNLOAD_ROOT = f"https://raw.githubusercontent.com/{REPOSITORY}/main"
ICON_NAME = "Classday.png"
ICON_URL = f"{DOWNLOAD_ROOT}/{ICON_NAME}"
IPA_RE = re.compile(r"^Classday-v([0-9]+\.[0-9]+\.[0-9]+)\.ipa$")
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
# AltStore ignores these; listing them makes SideStore treat the source as notarized or mismatched.
EXEMPT_ENTITLEMENTS = {
    "application-identifier",
    "com.apple.developer.team-identifier",
    "com.apple.security.get-task-allow",
}
FALLBACK_ENTITLEMENT = "com.apple.security.application-groups"


def semver_key(version: str) -> tuple[int, int, int]:
    parts = version.split(".")
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(version)
    return int(parts[0]), int(parts[1]), int(parts[2])


def should_publish(ref: str, current: str, parent: str | None) -> str:
    """Return 'publish' or a short reason the workflow should skip."""
    if not VERSION_RE.fullmatch(current or ""):
        return "current version is not X.Y.Z"
    if ref.startswith("refs/tags/v"):
        tag = ref.removeprefix("refs/tags/v")
        if VERSION_RE.fullmatch(tag) and tag != current:
            return f"tag {tag} does not match VERSION {current}"
        return "publish"
    if ref != "refs/heads/main":
        return "not main and not a v* tag"
    if not parent or parent == current:
        return "marketing version did not change"
    if not VERSION_RE.fullmatch(parent):
        return "parent version is not X.Y.Z"
    return "publish"


def tags_to_delete(current: str, tags: list[str]) -> list[str]:
    """GitHub Release tags to remove so only current and the previous semver remain."""
    parsed: list[tuple[tuple[int, int, int], str, str]] = []
    for tag in tags:
        name = tag[1:] if tag.startswith("v") else tag
        if not VERSION_RE.fullmatch(name):
            continue
        parsed.append((semver_key(name), tag, name))
    current_key = semver_key(current)
    below = [item for item in parsed if item[0] < current_key]
    keep = {current}
    if below:
        keep.add(max(below, key=lambda item: item[0])[2])
    return [tag for _, tag, name in parsed if name not in keep]


def decode_swift_string(value: str) -> str:
    def replace(match: re.Match[str]) -> str:
        token = match.group(0)
        if token == r"\n":
            return "\n"
        if token == r"\t":
            return "\t"
        if token == r"\"":
            return '"'
        if token == r"\\":
            return "\\"
        if token.startswith(r"\u") and len(token) == 6:
            return chr(int(token[2:], 16))
        return token

    return re.sub(r"\\u[0-9a-fA-F]{4}|\\[nt\"\\]", replace, value)


def changelog_description(source: str, version: str) -> str | None:
    pattern = re.compile(
        r'Entry\(\s*version:\s*"'
        + re.escape(version)
        + r'"\s*,\s*title:\s*"(?P<title>(?:\\.|[^"\\])*)"\s*,\s*changes:\s*\[(?P<body>.*?)\]\s*,?\s*\)',
        re.S,
    )
    match = pattern.search(source)
    if match is None:
        return None
    title = decode_swift_string(match.group("title"))
    lines = [decode_swift_string(raw) for raw in re.findall(r'"((?:\\.|[^"\\])*)"', match.group("body"))]
    if not lines:
        return title
    return title + "\n" + "\n".join(f"• {line}" for line in lines)


def ipa_metadata(path: Path) -> dict[str, object]:
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read("Payload/Classday.app/Info.plist"))
        entitlements: set[str] = set()
        privacy: dict[str, str] = {}
        for name in archive.namelist():
            if name.endswith("archived-expanded-entitlements.xcent") or name.endswith(".entitlements"):
                plist = plistlib.loads(archive.read(name))
                if isinstance(plist, dict):
                    entitlements.update(str(key) for key in plist)
            if name.endswith("Info.plist") and name.startswith("Payload/"):
                plist = plistlib.loads(archive.read(name))
                if isinstance(plist, dict):
                    for key, value in plist.items():
                        if str(key).endswith("UsageDescription") and isinstance(value, str):
                            privacy.setdefault(str(key), value)
    version = str(info.get("CFBundleShortVersionString", "")).strip()
    build = str(info.get("CFBundleVersion", "")).strip()
    if not VERSION_RE.fullmatch(version):
        raise SystemExit(f"{path.name} CFBundleShortVersionString is {version!r}")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise SystemExit(f"{path.name} CFBundleVersion is {build!r}")
    minimum = str(info.get("MinimumOSVersion") or "17.0")
    kept = sorted(item for item in entitlements if item not in EXEMPT_ENTITLEMENTS)
    if not kept:
        kept = [FALLBACK_ENTITLEMENT]
    return {
        "version": version,
        "build": build,
        "minimum": minimum,
        "entitlements": kept,
        "privacy": dict(sorted(privacy.items())),
        "size": path.stat().st_size,
    }


def git_file_date(repo: Path, filename: str) -> str | None:
    import subprocess

    result = subprocess.run(
        ["git", "log", "-1", "--format=%cs", "--", filename],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return None
    line = result.stdout.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", line):
        return line
    return None


def previous_notes(existing: dict | None, version: str) -> dict | None:
    if not existing:
        return None
    for app in existing.get("apps", []):
        if app.get("bundleIdentifier") != BUNDLE_ID:
            continue
        for item in app.get("versions", []):
            if item.get("version") == version:
                return item
    return None


def version_record(
    meta: dict[str, object],
    *,
    date: str,
    notes: str,
) -> dict[str, object]:
    version = str(meta["version"])
    return {
        "version": version,
        "buildVersion": str(meta["build"]),
        "date": date,
        "localizedDescription": notes,
        "downloadURL": f"{DOWNLOAD_ROOT}/Classday-v{version}.ipa",
        "size": int(meta["size"]),  # type: ignore[arg-type]
        "minOSVersion": str(meta["minimum"]),
    }


def update_releases(
    releases_dir: Path,
    ipa: Path,
    *,
    changelog_text: str,
    icon: Path | None,
    date: str,
) -> list[str]:
    """Copy the IPA, keep only current + previous, and rewrite apps.json.

    Returns the kept marketing versions, newest first.
    """
    releases_dir.mkdir(parents=True, exist_ok=True)
    current_meta = ipa_metadata(ipa)
    current = str(current_meta["version"])
    destination = releases_dir / f"Classday-v{current}.ipa"
    destination.write_bytes(ipa.read_bytes())
    if icon is not None and icon.is_file():
        (releases_dir / ICON_NAME).write_bytes(icon.read_bytes())

    found: list[tuple[tuple[int, int, int], Path]] = []
    for child in releases_dir.iterdir():
        match = IPA_RE.fullmatch(child.name)
        if match and child.is_file():
            found.append((semver_key(match.group(1)), child))
    found.sort(key=lambda item: item[0], reverse=True)
    current_key = semver_key(current)
    keep_paths = [destination]
    previous_path: Path | None = None
    for key, path in found:
        if key == current_key:
            continue
        if key < current_key and previous_path is None:
            previous_path = path
            keep_paths.append(path)
            continue
        path.unlink()
    for key, path in found:
        if path not in keep_paths and path.exists() and key != current_key:
            path.unlink()

    apps_path = releases_dir / "apps.json"
    existing = json.loads(apps_path.read_text(encoding="utf-8")) if apps_path.is_file() else None
    records = [
        version_record(
            current_meta,
            date=date,
            notes=changelog_description(changelog_text, current) or f"课曜 {current}",
        )
    ]
    if previous_path is not None:
        previous_meta = ipa_metadata(previous_path)
        previous = str(previous_meta["version"])
        prior = previous_notes(existing, previous) or {}
        records.append(
            version_record(
                previous_meta,
                date=str(prior.get("date") or git_file_date(releases_dir, previous_path.name) or date),
                notes=str(
                    prior.get("localizedDescription")
                    or changelog_description(changelog_text, previous)
                    or f"课曜 {previous}"
                ),
            )
        )

    document = {
        "name": SOURCE_NAME,
        "identifier": SOURCE_ID,
        "sourceURL": SOURCE_URL,
        "subtitle": "本地周课表",
        "description": "课曜 / Heptara。源里只有当前版和上一版的未签名安装包，用 SideStore 和免费 Apple ID 安装。",
        "iconURL": ICON_URL,
        "website": "https://github.com/yuanyeye0210-debug/classday-ios",
        "tintColor": "3A6BFF",
        "featuredApps": [BUNDLE_ID],
        "apps": [
            {
                "name": APP_NAME,
                "bundleIdentifier": BUNDLE_ID,
                "developerName": DEVELOPER_NAME,
                "subtitle": "本地周课表",
                "localizedDescription": "课曜 / Heptara 是装在 iPhone 上的本地周课表，带小组件。课程存在手机里。",
                "iconURL": ICON_URL,
                "tintColor": "3A6BFF",
                "category": "utilities",
                "versions": records,
                "appPermissions": {
                    "entitlements": current_meta["entitlements"],
                    "privacy": current_meta["privacy"],
                },
            }
        ],
        "news": [],
    }
    apps_path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return [str(record["version"]) for record in records]


def make_ipa(path: Path, version: str, build: str, *, privacy: dict[str, str] | None = None, entitlement: bool = True) -> None:
    info: dict[str, object] = {
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "CFBundleIdentifier": BUNDLE_ID,
        "MinimumOSVersion": "17.0",
    }
    if privacy:
        info.update(privacy)
    info_bytes = plistlib.dumps(info, fmt=plistlib.FMT_XML)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Classday.app/Info.plist", info_bytes)
        if entitlement:
            ent = plistlib.dumps(
                {FALLBACK_ENTITLEMENT: ["group.com.classday.shared"]},
                fmt=plistlib.FMT_XML,
            )
            archive.writestr("Payload/Classday.app/archived-expanded-entitlements.xcent", ent)


def self_test() -> None:
    assert should_publish("refs/tags/v2.7.2", "2.7.2", "2.7.1") == "publish"
    assert should_publish("refs/heads/main", "2.7.2", "2.7.1") == "publish"
    assert should_publish("refs/heads/main", "2.7.1", "2.7.1") != "publish"
    assert should_publish("refs/heads/main", "2.7.1", None) != "publish"
    assert should_publish("refs/heads/main", "2.7.1", "") != "publish"
    assert should_publish("refs/heads/cursor/old", "2.7.2", "2.7.1") != "publish"
    assert should_publish("refs/tags/v2.7.0", "2.7.1", "2.7.0") != "publish"

    deletes = tags_to_delete("2.7.1", ["v2.3.4", "v2.6.0", "v2.7.0", "v2.7.1", "not-a-release"])
    assert deletes == ["v2.3.4", "v2.6.0"], deletes
    deletes = tags_to_delete("2.8.0", ["v2.7.0", "v2.7.1", "v2.6.0"])
    assert deletes == ["v2.7.0", "v2.6.0"], deletes

    changelog = Path(__file__).resolve().parents[1] / "ClassdayCore" / "Sources" / "ClassdayCore" / "ScheduleExtras.swift"
    notes = changelog_description(changelog.read_text(encoding="utf-8"), "2.7.1")
    assert notes and "课程页" in notes and "•" in notes
    assert changelog_description("Entry(version: \"1.2.3\", title: \"Hi\", changes: [\n\"one\"\n]),", "1.2.3") == "Hi\n• one"
    assert changelog_description("nope", "9.9.9") is None

    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        releases = root / "releases"
        releases.mkdir()
        (releases / "README.md").write_text("keep\n", encoding="utf-8")
        make_ipa(releases / "Classday-v1.0.0.ipa", "1.0.0", "1")
        make_ipa(releases / "Classday-v1.1.0.ipa", "1.1.0", "2", privacy={"NSPhotoLibraryUsageDescription": "photos"})
        current = root / "Classday-v1.2.0.ipa"
        make_ipa(
            current,
            "1.2.0",
            "3",
            privacy={"NSCalendarsUsageDescription": "calendar"},
        )
        icon = root / "icon.png"
        icon.write_bytes(b"\x89PNG\r\n")
        notes_src = 'Entry(version: "1.2.0", title: "Newer", changes: [\n"fixed"\n]),\n'
        kept = update_releases(releases, current, changelog_text=notes_src, icon=icon, date="2026-11-12")
        assert kept == ["1.2.0", "1.1.0"], kept
        names = sorted(path.name for path in releases.iterdir())
        assert "Classday-v1.0.0.ipa" not in names
        assert "Classday-v1.1.0.ipa" in names
        assert "Classday-v1.2.0.ipa" in names
        assert "README.md" in names
        assert (releases / ICON_NAME).read_bytes() == b"\x89PNG\r\n"
        document = json.loads((releases / "apps.json").read_text(encoding="utf-8"))
        assert document["sourceURL"] == SOURCE_URL
        assert document["news"] == []
        app = document["apps"][0]
        assert app["bundleIdentifier"] == BUNDLE_ID
        assert app["iconURL"] == ICON_URL
        assert [item["version"] for item in app["versions"]] == ["1.2.0", "1.1.0"]
        newest = app["versions"][0]
        assert newest["buildVersion"] == "3"
        assert newest["date"] == "2026-11-12"
        assert newest["size"] == (releases / "Classday-v1.2.0.ipa").stat().st_size
        assert newest["minOSVersion"] == "17.0"
        assert newest["downloadURL"].endswith("/Classday-v1.2.0.ipa")
        assert "Newer" in newest["localizedDescription"]
        assert FALLBACK_ENTITLEMENT in app["appPermissions"]["entitlements"]
        assert app["appPermissions"]["privacy"]["NSCalendarsUsageDescription"] == "calendar"
        # A second publish of the same IPA keeps the previous notes and does not grow the list.
        kept_again = update_releases(releases, current, changelog_text=notes_src, icon=icon, date="2026-11-12")
        assert kept_again == ["1.2.0", "1.1.0"]
        again = json.loads((releases / "apps.json").read_text(encoding="utf-8"))
        assert again["apps"][0]["versions"][1]["version"] == "1.1.0"
    print("publish release self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    publish = sub.add_parser("should-publish")
    publish.add_argument("--ref", default="")
    publish.add_argument("--current", required=True)
    publish.add_argument("--parent", default="")

    plan = sub.add_parser("plan-deletes")
    plan.add_argument("--current", required=True)
    plan.add_argument("--tags-file", type=Path, required=True)

    update = sub.add_parser("update")
    update.add_argument("--releases", type=Path, required=True)
    update.add_argument("--ipa", type=Path, required=True)
    update.add_argument("--changelog", type=Path, required=True)
    update.add_argument("--icon", type=Path)
    update.add_argument("--date", required=True)

    sub.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "self-test":
        self_test()
        return 0
    if args.command == "should-publish":
        parent = args.parent.strip() or None
        print(should_publish(args.ref, args.current.strip(), parent))
        return 0
    if args.command == "plan-deletes":
        tags = [line.strip() for line in args.tags_file.read_text(encoding="utf-8").splitlines() if line.strip()]
        for tag in tags_to_delete(args.current.strip(), tags):
            print(tag)
        return 0
    kept = update_releases(
        args.releases,
        args.ipa,
        changelog_text=args.changelog.read_text(encoding="utf-8"),
        icon=args.icon,
        date=args.date,
    )
    print("kept " + " ".join(kept))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as error:
        if error.code in (None, 0):
            raise
        if str(error):
            print(error, file=sys.stderr)
        raise
