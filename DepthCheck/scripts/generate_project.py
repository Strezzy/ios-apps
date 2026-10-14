#!/usr/bin/env python3
"""Generate DepthCheck.xcodeproj without Homebrew, XcodeGen, or third-party Python.

Run again after adding sources. Native Swift packages keep their own target
boundaries; model manifests remain inside DepthCheckResources in the app.
"""
from __future__ import annotations

import plistlib
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = "DepthCheck"
BUNDLE = "com.billy.facet"
CONFIGURATION_PATH = ROOT / "scripts/project_config.json"


def configuration():
    """One explicit dependency/resource contract for generation and packaging."""
    data = json.loads(CONFIGURATION_PATH.read_text())
    if data.get("app") != APP or data.get("bundle_identifier") != BUNDLE:
        raise ValueError("The build configuration does not describe DepthCheck")
    return data


CONFIGURATION = configuration()
REMOTE_PACKAGES = tuple((item["name"], item["url"], item["revision"], item["product"])
                        for item in CONFIGURATION.get("remote_packages", []))
LOCAL_PACKAGES = tuple((item["name"], item["path"], item["product"])
                       for item in CONFIGURATION.get("local_packages", []))
SOURCE_TYPES = {
    ".swift": "sourcecode.swift", ".metal": "sourcecode.metal", ".m": "sourcecode.c.objc",
    ".mm": "sourcecode.cpp.objcpp", ".c": "sourcecode.c.c",
    ".cpp": "sourcecode.cpp.cpp", ".h": "sourcecode.c.h",
}


def identifier(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def openstep(value, indent=0) -> str:
    prefix = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (indent + 1) + quote(str(key)) + " = "
                         + openstep(item, indent + 1) + ";")
        return "\n".join(lines) + "\n" + prefix + "}"
    if isinstance(value, (list, tuple)):
        if not value:
            return "()"
        return "(\n" + "\n".join("\t" * (indent + 1)
                + openstep(item, indent + 1) + "," for item in value) + "\n" + prefix + ")"
    if isinstance(value, int):
        return str(value)
    return quote(str(value))


class Project:
    def __init__(self):
        self.objects = {}

    def add(self, key, isa, **values):
        uid = identifier(key)
        if uid in self.objects:
            raise ValueError("Duplicate Xcode object key: " + key)
        self.objects[uid] = {"isa": isa, **values}
        return uid

    def file(self, path, file_type=None):
        rel = path.relative_to(ROOT).as_posix()
        kind = file_type or SOURCE_TYPES.get(path.suffix, {
            ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml",
            ".plist": "text.plist.xml", ".json": "text.json",
        }.get(path.suffix, "text"))
        return self.add("file:" + rel, "PBXFileReference", lastKnownFileType=kind,
                        path=rel, sourceTree="SOURCE_ROOT")

    def phase_file(self, target, file_ref, path):
        return self.add("build:" + target + ":" + str(path), "PBXBuildFile", fileRef=file_ref)


def app_files(project):
    references, sources, resources = [], [], []
    root = ROOT / APP
    excluded = [(ROOT / path).resolve() for _, path, _ in LOCAL_PACKAGES]
    # A top-level Resources directory changes CFBundle's layout detection and
    # can hide the app's root Info.plist from the iOS installer.
    resource_root = root / "DepthCheckResources"
    if resource_root.is_dir():
        ref = project.file(resource_root, "folder")
        references.append(ref)
        resources.append(project.phase_file(APP, ref, resource_root))
    for path in sorted(root.rglob("*")):
        if any(path == package or package in path.parents for package in excluded):
            continue
        if path == resource_root or resource_root in path.parents:
            continue
        if any(part.startswith(".") for part in path.relative_to(root).parts):
            continue
        if any(parent.suffix == ".xcassets" for parent in path.parents):
            continue
        if path.is_dir() and path.suffix != ".xcassets":
            continue
        ref = project.file(path)
        references.append(ref)
        if path.suffix in SOURCE_TYPES and path.suffix != ".h":
            sources.append(project.phase_file(APP, ref, path))
        elif path.name not in ("Info.plist",) and path.suffix not in (".h",):
            resources.append(project.phase_file(APP, ref, path))
    return references, sources, resources


def config_list(project, name, common, debug=None, release=None):
    refs = []
    for variant, extra in (("Debug", debug or {}), ("Release", release or {})):
        refs.append(project.add("config:" + name + ":" + variant,
            "XCBuildConfiguration", buildSettings={**common, **extra}, name=variant))
    return project.add("configlist:" + name, "XCConfigurationList",
        buildConfigurations=refs, defaultConfigurationIsVisible=0,
        defaultConfigurationName="Release")


def target_phases(project, target, sources, resources, package_refs):
    product_refs, linked_products = [], []
    for package_ref, product_name in package_refs:
        product_ref = project.add("product:" + target + ":" + product_name,
            "XCSwiftPackageProductDependency", package=package_ref, productName=product_name)
        product_refs.append(product_ref)
        linked_products.append(project.add("packagebuild:" + target + ":" + product_name,
            "PBXBuildFile", productRef=product_ref))
    phases = []
    for name, kind, files in (("sources", "PBXSourcesBuildPhase", sources),
                             ("frameworks", "PBXFrameworksBuildPhase", linked_products),
                             ("resources", "PBXResourcesBuildPhase", resources)):
        phases.append(project.add("phase:" + target + ":" + name, kind,
            buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0))
    return phases, product_refs


def generate():
    project = Project()
    app_refs, sources, resources = app_files(project)
    packages, package_products = [], []
    for name, url, revision, product in REMOTE_PACKAGES:
        if not re.fullmatch("[0-9a-f]{40}", revision):
            raise ValueError("Package revision must be a complete immutable commit")
        ref = project.add("package:" + name, "XCRemoteSwiftPackageReference",
            repositoryURL=url, requirement={"kind": "revision", "revision": revision})
        packages.append(ref)
        package_products.append((ref, product))
    for name, path, product in LOCAL_PACKAGES:
        ref = project.add("package:" + name, "XCLocalSwiftPackageReference", relativePath=path)
        packages.append(ref)
        package_products.append((ref, product))
    app_product = project.add("app-product", "PBXFileReference", explicitFileType="wrapper.application",
        includeInIndex=0, path=APP + ".app", sourceTree="BUILT_PRODUCTS_DIR")
    common_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES", "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES", "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted",
    }
    project_config = config_list(project, "project", common_settings,
        debug={"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
               "ONLY_ACTIVE_ARCH": "YES",
               "GCC_OPTIMIZATION_LEVEL": "0", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
               "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"},
        release={"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule",
                 "SWIFT_OPTIMIZATION_LEVEL": "-O", "VALIDATE_PRODUCT": "YES"})
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": str(plistlib.loads((ROOT / APP / "Info.plist").read_bytes())["CFBundleVersion"]),
        "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": APP + "/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "1.1", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE,
        "PRODUCT_NAME": "$(TARGET_NAME)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": "1",
    }
    app_config = config_list(project, APP, target_settings)
    app_phases, app_packages = target_phases(project, APP, sources, resources, package_products)
    app_target = project.add("app-target", "PBXNativeTarget", buildConfigurationList=app_config,
        buildPhases=app_phases, buildRules=[], dependencies=[], name=APP,
        packageProductDependencies=app_packages, productName=APP, productReference=app_product,
        productType="com.apple.product-type.application")
    all_targets, products, groups = [app_target], [app_product], []
    groups.append(project.add("app-group", "PBXGroup", children=app_refs, name=APP, sourceTree="<group>"))
    test_files = sorted((ROOT / "DepthCheckTests").rglob("*.swift"))
    test_target = None
    if test_files:
        test_refs, test_sources = [], []
        for path in test_files:
            ref = project.file(path)
            test_refs.append(ref)
            test_sources.append(project.phase_file(APP + "Tests", ref, path))
        groups.append(project.add("test-group", "PBXGroup", children=test_refs,
                                  name=APP + "Tests", sourceTree="<group>"))
        test_product = project.add("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle",
            includeInIndex=0, path=APP + "Tests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
        products.append(test_product)
        test_config = config_list(project, APP + "Tests", {
            "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".tests", "PRODUCT_NAME": "$(TARGET_NAME)",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/DepthCheck.app/DepthCheck",
            "BUNDLE_LOADER": "$(TEST_HOST)", "TARGETED_DEVICE_FAMILY": "1",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        })
        proxy = project.add("test-app-proxy", "PBXContainerItemProxy",
            containerPortal=identifier("project"), proxyType=1,
            remoteGlobalIDString=app_target, remoteInfo=APP)
        dependency = project.add("test-app-dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
        requested_test_products = set(CONFIGURATION.get("test_package_products", []))
        test_package_products = [entry for entry in package_products if entry[1] in requested_test_products]
        if {entry[1] for entry in test_package_products} != requested_test_products:
            raise ValueError("A requested XCTest package product is not included by the app")
        test_phases, test_packages = target_phases(project, APP + "Tests", test_sources, [], test_package_products)
        test_target = project.add("test-target", "PBXNativeTarget", buildConfigurationList=test_config,
            buildPhases=test_phases, buildRules=[], dependencies=[dependency], name=APP + "Tests",
            packageProductDependencies=test_packages, productName=APP + "Tests", productReference=test_product,
            productType="com.apple.product-type.bundle.unit-test")
        all_targets.append(test_target)
    product_group = project.add("products-group", "PBXGroup", children=products,
                                name="Products", sourceTree="<group>")
    groups.append(product_group)
    main_group = project.add("main-group", "PBXGroup", children=groups, sourceTree="<group>")
    attributes = {"LastUpgradeCheck": "2600", "BuildIndependentTargetsInParallel": "YES",
        "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "26.0"}}}
    if test_target:
        attributes["TargetAttributes"][test_target] = {"CreatedOnToolsVersion": "26.0", "TestTargetID": app_target}
    project_ref = project.add("project", "PBXProject", attributes=attributes,
        buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0",
        developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
        mainGroup=main_group, packageReferences=packages, productRefGroup=product_group,
        projectDirPath="", projectRoot="", targets=all_targets)
    folder = ROOT / (APP + ".xcodeproj")
    folder.mkdir(parents=True, exist_ok=True)
    document = {"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                "objects": project.objects, "rootObject": project_ref}
    (folder / "project.pbxproj").write_text("// !$*UTF8*$!\n" + openstep(document) + "\n")
    schemes = folder / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    app_reference = (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" '
        f'BuildableName="{APP}.app" BlueprintName="{APP}" ReferencedContainer="container:{APP}.xcodeproj"/>')
    test_references = ""
    if test_target:
        test_references = (f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" '
            f'BlueprintIdentifier="{test_target}" BuildableName="{APP}Tests.xctest" BlueprintName="{APP}Tests" '
            f'ReferencedContainer="container:{APP}.xcodeproj"/></TestableReference>')
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_reference}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{test_references}</Testables><MacroExpansion>{app_reference}</MacroExpansion></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (schemes / (APP + ".xcscheme")).write_text(scheme)
    workspace = folder / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
    evidence = {"app": APP, "app_source_count": len(sources), "test_source_count": len(test_files),
        "resource_build_entries": len(resources), "deployment_target": "26.0",
        "remote_packages": [{"url": url, "revision": revision, "product": product}
                            for _, url, revision, product in REMOTE_PACKAGES],
        "local_packages": [{"path": path, "product": product} for _, path, product in LOCAL_PACKAGES],
        "has_tests": bool(test_files), "project": str(folder)}
    metadata = ROOT / ".build/generated-project.json"
    metadata.parent.mkdir(exist_ok=True)
    metadata.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))
    return evidence


if __name__ == "__main__":
    generate()

