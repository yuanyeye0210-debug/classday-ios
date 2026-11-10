#!/usr/bin/env python3
"""Write Classday.xcodeproj from the source tree.

The checked-in project is the output of this script. Run it from anywhere:

    python3 Classday/Tools/generate_xcodeproj.py

It does not call Xcode or XcodeGen. Open the generated project with Xcode 16 or newer.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def marketing_version() -> str:
    line = (ROOT / "VERSION").read_text(encoding="utf-8").splitlines()[0].strip()
    parts = line.split(".")
    if len(parts) != 3 or not all(part.isdigit() and part != "" for part in parts):
        raise SystemExit(f"Classday/VERSION must look like 1.2.3, got {line!r}")
    return line


def sync_project_yml(version: str) -> None:
    import re

    path = ROOT / "project.yml"
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(MARKETING_VERSION:\s*")[^"]+(")',
        rf"\g<1>{version}\2",
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("project.yml MARKETING_VERSION was not updated")
    path.write_text(updated, encoding="utf-8")
APP_SOURCES = sorted((ROOT / "ClassdayApp" / "Sources").glob("*.swift"))
WIDGET_SOURCES = sorted((ROOT / "ClassdayWidget" / "Sources").glob("*.swift"))
PROJECT = ROOT / "Classday.xcodeproj"
APP_TARGET = "C0DE000000000000000000A1"
WIDGET_TARGET = "C0DE000000000000000000B1"
PROJECT_ID = "C0DE00000000000000000001"
PKG = "C0DE000000000000000000F1"
PROD_APP = "C0DE000000000000000000F2"
PROD_WIDGET = "C0DE000000000000000000F3"


def xid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def pbx_quote(value: str) -> str:
    # Quote anything the pbx parser would not treat as a bare identifier.
    # Leading "-" matters: SWIFT_OPTIMIZATION_LEVEL = -Onone is invalid unquoted.
    if value and all(ch.isalnum() or ch in "._/" for ch in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def build_settings(settings: dict[str, str | list[str]], indent: str = "\t\t\t\t") -> str:
    lines = []
    for key in settings:
        value = settings[key]
        if isinstance(value, list):
            inner = ", ".join(pbx_quote(item) for item in value)
            lines.append(f"{indent}{key} = ({inner});")
        else:
            lines.append(f"{indent}{key} = {pbx_quote(value)};")
    return "\n".join(lines)


def file_ref(path: Path, kind: str) -> tuple[str, str]:
    ref = xid(f"ref:{path.as_posix()}")
    name = path.name
    return ref, (
        f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = {kind}; path = {name}; sourceTree = \"<group>\"; }};"
    )


def main() -> None:
    if not APP_SOURCES or not WIDGET_SOURCES:
        raise SystemExit("missing Swift sources")
    version = marketing_version()
    sync_project_yml(version)

    objects: list[str] = []
    app_build_files: list[str] = []
    widget_build_files: list[str] = []
    app_file_refs: list[tuple[str, str]] = []
    widget_file_refs: list[tuple[str, str]] = []

    def add_source(path: Path, target_seed: str, bucket: list[str], refs: list[tuple[str, str]]) -> None:
        ref, declaration = file_ref(path, "sourcecode.swift")
        build = xid(f"build:{target_seed}:{path.as_posix()}")
        objects.append(declaration)
        objects.append(
            f"\t\t{build} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
        )
        bucket.append(f"\t\t\t\t{build} /* {path.name} in Sources */,")
        refs.append((ref, path.name))

    for path in APP_SOURCES:
        add_source(path, "app", app_build_files, app_file_refs)
    metal_children: list[str] = []
    for path in sorted((ROOT / "ClassdayShaders.metal",)):
        if path.is_file():
            ref, declaration = file_ref(path, "sourcecode.metal")
            build = xid(f"build:metal:{path.as_posix()}")
            objects.append(declaration)
            objects.append(
                f"\t\t{build} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {path.name} */; }};"
            )
            app_build_files.append(f"\t\t\t\t{build} /* {path.name} in Sources */,")
            metal_children.append(f"{ref} /* {path.name} */")
    for path in WIDGET_SOURCES:
        add_source(path, "widget", widget_build_files, widget_file_refs)

    assets_ref, assets_decl = file_ref(ROOT / "ClassdayApp" / "Assets.xcassets", "folder.assetcatalog")
    assets_build = xid("build:assets")
    objects.append(assets_decl)
    objects.append(
        f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};"
    )

    config_files = [
        ROOT / "Config" / "Classday-Info.plist",
        ROOT / "Config" / "Classday.entitlements",
        ROOT / "Config" / "ClassdayWidget-Info.plist",
        ROOT / "Config" / "ClassdayWidget.entitlements",
    ]
    config_refs = []
    for path in config_files:
        kind = "text.plist.entitlements" if path.suffix == ".entitlements" else "text.plist.xml"
        ref, declaration = file_ref(path, kind)
        objects.append(declaration)
        config_refs.append((ref, path.name))

    app_product = xid("product:app")
    widget_product = xid("product:widget")
    objects.append(
        f"\t\t{app_product} /* Classday.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Classday.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    objects.append(
        f"\t\t{widget_product} /* ClassdayWidget.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ClassdayWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )

    embed = xid("embed:widget")
    objects.append(
        f"\t\t{embed} /* ClassdayWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {widget_product} /* ClassdayWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    link_app = xid("link:app")
    link_widget = xid("link:widget")
    objects.append(f"\t\t{link_app} /* ClassdayCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {PROD_APP} /* ClassdayCore */; }};")
    objects.append(
        f"\t\t{link_widget} /* ClassdayCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {PROD_WIDGET} /* ClassdayCore */; }};"
    )

    app_sources_phase = xid("phase:app-sources")
    widget_sources_phase = xid("phase:widget-sources")
    app_frameworks_phase = xid("phase:app-frameworks")
    widget_frameworks_phase = xid("phase:widget-frameworks")
    app_resources_phase = xid("phase:app-resources")
    widget_resources_phase = xid("phase:widget-resources")
    embed_phase = xid("phase:embed")

    def phase(phase_id: str, isa: str, name: str, files: list[str], extra: str = "") -> str:
        body = "\n".join(files)
        return (
            f"\t\t{phase_id} /* {name} */ = {{\n"
            f"\t\t\tisa = {isa};\n"
            f"\t\t\tbuildActionMask = 2147483647;\n"
            f"{extra}"
            f"\t\t\tfiles = (\n{body}\n\t\t\t);\n"
            f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            f"\t\t}};"
        )

    objects.append(phase(app_sources_phase, "PBXSourcesBuildPhase", "Sources", app_build_files))
    objects.append(phase(widget_sources_phase, "PBXSourcesBuildPhase", "Sources", widget_build_files))
    objects.append(phase(app_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", [f"\t\t\t\t{link_app} /* ClassdayCore in Frameworks */,"]))
    objects.append(phase(widget_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", [f"\t\t\t\t{link_widget} /* ClassdayCore in Frameworks */,"]))
    en_strings = xid("ref:infoplist:en")
    zh_strings = xid("ref:infoplist:zh-Hans")
    strings_variant = xid("variant:infoplist")
    objects.append(
        f"\t\t{en_strings} /* en */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/InfoPlist.strings; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{zh_strings} /* zh-Hans */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = \"zh-Hans\"; path = \"zh-Hans.lproj/InfoPlist.strings\"; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{strings_variant} /* InfoPlist.strings */ = {{\n"
        f"\t\t\tisa = PBXVariantGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{en_strings} /* en */,\n"
        f"\t\t\t\t{zh_strings} /* zh-Hans */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = InfoPlist.strings;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    app_strings_build = xid("build:app-infoplist-strings")
    widget_strings_build = xid("build:widget-infoplist-strings")
    widget_assets_build = xid("build:widget-assets")
    objects.append(
        f"\t\t{app_strings_build} /* InfoPlist.strings in Resources */ = {{isa = PBXBuildFile; fileRef = {strings_variant} /* InfoPlist.strings */; }};"
    )
    objects.append(
        f"\t\t{widget_strings_build} /* InfoPlist.strings in Resources */ = {{isa = PBXBuildFile; fileRef = {strings_variant} /* InfoPlist.strings */; }};"
    )
    objects.append(
        f"\t\t{widget_assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};"
    )
    objects.append(phase(
        app_resources_phase,
        "PBXResourcesBuildPhase",
        "Resources",
        [
            f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,",
            f"\t\t\t\t{app_strings_build} /* InfoPlist.strings in Resources */,",
        ],
    ))
    objects.append(phase(
        widget_resources_phase,
        "PBXResourcesBuildPhase",
        "Resources",
        [
            f"\t\t\t\t{widget_assets_build} /* Assets.xcassets in Resources */,",
            f"\t\t\t\t{widget_strings_build} /* InfoPlist.strings in Resources */,",
        ],
    ))
    objects.append(
        phase(
            embed_phase,
            "PBXCopyFilesBuildPhase",
            "Embed Foundation Extensions",
            [f"\t\t\t\t{embed} /* ClassdayWidget.appex in Embed Foundation Extensions */,"],
            extra=(
                "\t\t\tdstPath = \"\";\n"
                "\t\t\tdstSubfolderSpec = 13;\n"
                "\t\t\tname = \"Embed Foundation Extensions\";\n"
            ),
        )
    )

    def group(group_id: str, name: str, path: str | None, children: list[str]) -> str:
        child_lines = "\n".join(f"\t\t\t\t{child}," for child in children)
        path_line = f"\t\t\tpath = {path};\n" if path else ""
        name_line = f"\t\t\tname = {name};\n" if path is None else ""
        return (
            f"\t\t{group_id} /* {name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n{child_lines}\n\t\t\t);\n"
            f"{name_line}{path_line}"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )

    app_sources_group = xid("group:app-sources")
    widget_sources_group = xid("group:widget-sources")
    app_group = xid("group:app")
    widget_group = xid("group:widget")
    config_group = xid("group:config")
    products_group = xid("group:products")
    root_group = xid("group:root")

    objects.append(group(app_sources_group, "Sources", "Sources", [f"{ref} /* {name} */" for ref, name in app_file_refs]))
    objects.append(group(widget_sources_group, "Sources", "Sources", [f"{ref} /* {name} */" for ref, name in widget_file_refs]))
    objects.append(
        group(
            app_group,
            "ClassdayApp",
            "ClassdayApp",
            [f"{app_sources_group} /* Sources */", f"{assets_ref} /* Assets.xcassets */"],
        )
    )
    objects.append(group(widget_group, "ClassdayWidget", "ClassdayWidget", [f"{widget_sources_group} /* Sources */"]))
    objects.append(group(
        config_group,
        "Config",
        "Config",
        [f"{ref} /* {name} */" for ref, name in config_refs] + [f"{strings_variant} /* InfoPlist.strings */"],
    ))
    objects.append(
        group(
            products_group,
            "Products",
            None,
            [f"{app_product} /* Classday.app */", f"{widget_product} /* ClassdayWidget.appex */"],
        )
    )
    objects.append(
        group(
            root_group,
            "Classday",
            None,
            [
                f"{app_group} /* ClassdayApp */",
                f"{widget_group} /* ClassdayWidget */",
                f"{config_group} /* Config */",
                *metal_children,
                f"{products_group} /* Products */",
            ],
        )
    )

    proxy = xid("proxy:widget")
    dependency = xid("dep:widget")
    objects.append(
        f"\t\t{proxy} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {PROJECT_ID} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {WIDGET_TARGET};\n"
        f"\t\t\tremoteInfo = ClassdayWidget;\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{dependency} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {WIDGET_TARGET} /* ClassdayWidget */;\n"
        f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n"
        f"\t\t}};"
    )

    app_debug = xid("cfg:app-debug")
    app_release = xid("cfg:app-release")
    widget_debug = xid("cfg:widget-debug")
    widget_release = xid("cfg:widget-release")
    proj_debug = xid("cfg:proj-debug")
    proj_release = xid("cfg:proj-release")
    app_list = xid("list:app")
    widget_list = xid("list:widget")
    proj_list = xid("list:proj")

    common_target = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MARKETING_VERSION": version,
        "SDKROOT": "iphoneos",
        "SKIP_INSTALL": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    app_settings = {
        **common_target,
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "Config/Classday.entitlements",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "Config/Classday-Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "OTHER_LDFLAGS": ["$(inherited)", "-weak_framework", "CloudKit"],
        "PRODUCT_BUNDLE_IDENTIFIER": "com.classday.app",
        "PRODUCT_NAME": "$(TARGET_NAME)",
    }
    widget_settings = {
        **common_target,
        "APPLICATION_EXTENSION_API_ONLY": "YES",
        "CODE_SIGN_ENTITLEMENTS": "Config/ClassdayWidget.entitlements",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Config/ClassdayWidget-Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
        "PRODUCT_BUNDLE_IDENTIFIER": "com.classday.app.widget",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SKIP_INSTALL": "YES",
    }

    def configuration(config_id: str, name: str, settings: dict[str, str | list[str]]) -> str:
        return (
            f"\t\t{config_id} /* {name} */ = {{\n"
            f"\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n{build_settings(settings)}\n\t\t\t}};\n"
            f"\t\t\tname = {name};\n"
            f"\t\t}};"
        )

    debug_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_VERSION": "5.0",
    }
    release_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SDKROOT": "iphoneos",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "SWIFT_VERSION": "5.0",
        "VALIDATE_PRODUCT": "YES",
    }
    objects.append(configuration(proj_debug, "Debug", debug_project))
    objects.append(configuration(proj_release, "Release", release_project))
    objects.append(configuration(app_debug, "Debug", app_settings))
    objects.append(configuration(app_release, "Release", app_settings))
    objects.append(configuration(widget_debug, "Debug", widget_settings))
    objects.append(configuration(widget_release, "Release", widget_settings))

    def config_list(list_id: str, name: str, debug_id: str, release_id: str) -> str:
        return (
            f"\t\t{list_id} /* Build configuration list for {name} */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{debug_id} /* Debug */,\n"
            f"\t\t\t\t{release_id} /* Release */,\n"
            f"\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = Release;\n"
            f"\t\t}};"
        )

    objects.append(config_list(proj_list, "PBXProject", proj_debug, proj_release))
    objects.append(config_list(app_list, "PBXNativeTarget Classday", app_debug, app_release))
    objects.append(config_list(widget_list, "PBXNativeTarget ClassdayWidget", widget_debug, widget_release))

    objects.append(
        f"\t\t{APP_TARGET} /* Classday */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {app_list} /* Build configuration list for PBXNativeTarget Classday */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{app_sources_phase} /* Sources */,\n"
        f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{app_resources_phase} /* Resources */,\n"
        f"\t\t\t\t{embed_phase} /* Embed Foundation Extensions */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t\t{dependency} /* PBXTargetDependency */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = Classday;\n"
        f"\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{PROD_APP} /* ClassdayCore */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = Classday;\n"
        f"\t\t\tproductReference = {app_product} /* Classday.app */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.application\";\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{WIDGET_TARGET} /* ClassdayWidget */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {widget_list} /* Build configuration list for PBXNativeTarget ClassdayWidget */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{widget_sources_phase} /* Sources */,\n"
        f"\t\t\t\t{widget_frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{widget_resources_phase} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t);\n"
        f"\t\t\tname = ClassdayWidget;\n"
        f"\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{PROD_WIDGET} /* ClassdayCore */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = ClassdayWidget;\n"
        f"\t\t\tproductReference = {widget_product} /* ClassdayWidget.appex */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{PROJECT_ID} /* Project object */ = {{\n"
        f"\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n"
        f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
        f"\t\t\t\tLastUpgradeCheck = 1600;\n"
        f"\t\t\t\tORGANIZATIONNAME = Classday;\n"
        f"\t\t\t\tTargetAttributes = {{\n"
        f"\t\t\t\t\t{APP_TARGET} = {{ CreatedOnToolsVersion = 16.0; }};\n"
        f"\t\t\t\t\t{WIDGET_TARGET} = {{ CreatedOnToolsVersion = 16.0; }};\n"
        f"\t\t\t\t}};\n"
        f"\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {proj_list} /* Build configuration list for PBXProject */;\n"
        f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
        f"\t\t\tdevelopmentRegion = \"zh-Hans\";\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n"
        f"\t\t\t\ten,\n"
        f"\t\t\t\tBase,\n"
        f"\t\t\t\t\"zh-Hans\",\n"
        f"\t\t\t);\n"
        f"\t\t\tmainGroup = {root_group} /* Classday */;\n"
        f"\t\t\tpackageReferences = (\n"
        f"\t\t\t\t{PKG} /* XCLocalSwiftPackageReference \"ClassdayCore\" */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        f"\t\t\tprojectDirPath = \"\";\n"
        f"\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = (\n"
        f"\t\t\t\t{APP_TARGET} /* Classday */,\n"
        f"\t\t\t\t{WIDGET_TARGET} /* ClassdayWidget */,\n"
        f"\t\t\t);\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{PKG} /* XCLocalSwiftPackageReference \"ClassdayCore\" */ = {{\n"
        f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
        f"\t\t\trelativePath = ClassdayCore;\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{PROD_APP} /* ClassdayCore */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {PKG} /* XCLocalSwiftPackageReference \"ClassdayCore\" */;\n"
        f"\t\t\tproductName = ClassdayCore;\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{PROD_WIDGET} /* ClassdayCore */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {PKG} /* XCLocalSwiftPackageReference \"ClassdayCore\" */;\n"
        f"\t\t\tproductName = ClassdayCore;\n"
        f"\t\t}};"
    )

    pbx = "\n".join(
        [
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = 56;",
            "\tobjects = {",
            "",
            *objects,
            "\t};",
            f"\trootObject = {PROJECT_ID} /* Project object */;",
            "}",
            "",
        ]
    )
    proj_dir = PROJECT
    proj_dir.mkdir(parents=True, exist_ok=True)
    (proj_dir / "project.pbxproj").write_text(pbx, encoding="utf-8")
    workspace = proj_dir / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
""",
        encoding="utf-8",
    )
    schemes = proj_dir / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "Classday.xcscheme").write_text(scheme(APP_TARGET), encoding="utf-8")
    print(f"wrote {proj_dir / 'project.pbxproj'}")
    print(f"app sources: {len(APP_SOURCES)} widget sources: {len(WIDGET_SOURCES)}")


def scheme(app_target: str) -> str:
    ref = f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Classday.app"
               BlueprintName = "Classday"
               ReferencedContainer = "container:Classday.xcodeproj">
            </BuildableReference>"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    main()
