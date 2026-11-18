#!/usr/bin/env python3
"""Static checks for the Classday Xcode project. Does not compile SwiftUI or WidgetKit."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "Classday.xcodeproj" / "project.pbxproj"
failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def read(path: Path) -> str:
    check(path.is_file(), f"missing {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def main() -> int:
    pbx = read(PBX)
    app_sources = sorted((ROOT / "ClassdayApp" / "Sources").glob("*.swift"))
    widget_sources = sorted((ROOT / "ClassdayWidget" / "Sources").glob("*.swift"))
    check(bool(app_sources), "no app sources")
    check(bool(widget_sources), "no widget sources")
    for path in app_sources + widget_sources:
        check(path.name in pbx, f"{path.name} is not referenced by the Xcode project")

    check('productType = "com.apple.product-type.application"' in pbx, "app product type missing")
    check('productType = "com.apple.product-type.app-extension"' in pbx, "widget product type missing")
    check("com.apple.widgetkit-extension" in read(ROOT / "Config" / "ClassdayWidget-Info.plist"), "widget extension point missing")
    check("classday" in read(ROOT / "Config" / "Classday-Info.plist"), "url scheme missing")
    for name in ("Classday.entitlements", "ClassdayWidget.entitlements"):
        text = read(ROOT / "Config" / name)
        check("group.com.classday.shared" in text, f"{name} missing app group")
    resolver = read(ROOT / "ClassdayCore" / "Sources" / "ClassdayCore" / "AppGroupResolver.swift")
    check('identifier = "group.com.classday.shared"' in resolver, "AppGroup identifier drifted")
    check("embedded.mobileprovision" in resolver, "resolver does not read the provisioning profile")
    check("forSecurityApplicationGroupIdentifier" in resolver, "resolver does not probe the group container")
    check("UserDefaults" in resolver, "resolver does not probe UserDefaults")
    check("Remove Extensions" in resolver, "Sideloadly warning lost Remove Extensions")
    for name in ("Classday-Info.plist", "ClassdayWidget-Info.plist"):
        plist = read(ROOT / "Config" / name)
        check("ALTAppGroups" in plist and "group.com.classday.shared" in plist, f"{name} missing ALTAppGroups")
    model = read(ROOT / "ClassdayCore" / "Sources" / "ClassdayCore" / "Models.swift")
    check("NextClassWidget" in model and "TodayCoursesWidget" in model, "widget kind constants missing")
    check("WidgetID.nextClass" in read(ROOT / "ClassdayWidget" / "Sources" / "ClassdayWidgetBundle.swift"), "widget kind not used")
    check("WidgetID.todayCourses" in read(ROOT / "ClassdayWidget" / "Sources" / "ClassdayWidgetBundle.swift"), "today widget kind not used")
    check(".systemSmall" in pbx or ".systemSmall" in read(ROOT / "ClassdayWidget" / "Sources" / "ClassdayWidgetBundle.swift"), "small family missing")
    check("APPLICATION_EXTENSION_API_ONLY" in pbx, "widget is not marked extension-API-only")
    check("IPHONEOS_DEPLOYMENT_TARGET = 17.0" in pbx, "deployment target is not 17.0")
    check("com.classday.app.widget" in pbx and "com.classday.app" in pbx, "bundle ids missing")
    check("ClassdayCore" in pbx, "local package missing")
    check("PBXCopyFilesBuildPhase" in pbx and "dstSubfolderSpec = 13" in pbx, "widget is not embedded")

    version_path = ROOT / "VERSION"
    if version_path.is_file():
        version = version_path.read_text(encoding="utf-8").strip()
    else:
        check(False, "missing Classday/VERSION")
        version = None
    if version is not None:
        check(f'MARKETING_VERSION: "{version}"' in (ROOT / "project.yml").read_text(encoding="utf-8"), "project.yml version drifted from VERSION")
        check(f"MARKETING_VERSION = {version};" in pbx, "pbxproj version drifted from VERSION")
    check((ROOT / "Tools" / "bump-version.sh").is_file(), "bump-version.sh missing")

    archive = ROOT / "VersionArchive"
    marker = (archive / ".classday-backup-root").read_text(encoding="utf-8")
    check(marker == "classday-version-archive-v1\n", "backup marker is wrong")
    directory_names = sorted(child.name for child in archive.iterdir() if child.is_dir() and not child.is_symlink())
    check(directory_names in ([], ["previous"]), f"VersionArchive directories must be only previous, found {directory_names}")
    previous = archive / "previous"
    if previous.exists():
        stamp = (previous / ".classday-snapshot-version").read_text(encoding="utf-8").strip()
        captured = (previous / "VERSION").read_text(encoding="utf-8").strip()
        check(stamp == captured and (version is None or stamp != version), "previous snapshot must be the replaced version, not the current one")
        check(not (previous / "VersionArchive").exists(), "previous snapshot contains a nested archive")
    elif version is not None:
        check(version == "1.0.0", "VERSION changed without a previous snapshot; use Tools/bump-version.sh")

    joined = "\n".join(path.read_text(encoding="utf-8") for path in app_sources + widget_sources)
    for banned in ("校园登录", "成绩查询", "密码登录"):
        check(banned not in joined, f"found disallowed copy: {banned}")
    check("import WidgetKit" in read(ROOT / "ClassdayWidget" / "Sources" / "ClassdayWidgetBundle.swift"), "widget target does not import WidgetKit")
    check("TimelineProvider" in read(ROOT / "ClassdayWidget" / "Sources" / "ClassdayWidgetBundle.swift"), "widget has no timeline provider")
    check("containerBackground" in read(ROOT / "ClassdayWidget" / "Sources" / "WidgetViews.swift"), "widget background modifier missing")

    # The shared-data import sheet belongs to the root view so a request from
    # Settings, a deep link, or the data page presents no matter which tab is
    # active. Mounting it inside TodayView silently swallowed those requests.
    root_view = read(ROOT / "ClassdayApp" / "Sources" / "RootView.swift")
    import_sheet = ".sheet(isPresented: $model.showSmartImport)"
    today_view = root_view.find("struct TodayView")
    check(
        root_view.count(import_sheet) == 1 and 0 <= root_view.find(import_sheet) < today_view,
        "shared import sheet must be mounted on the root view, before TodayView",
    )
    check(
        not any(
            "SmartImportView()" in path.read_text(encoding="utf-8")
            for path in app_sources
            if path.name != "RootView.swift"
        ),
        "SmartImportView must only be presented by the root view",
    )

    if failures:
        print("project check failed:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print(f"project check passed ({len(app_sources)} app sources, {len(widget_sources)} widget sources)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
