#!/usr/bin/env python3
"""Generate an ordinary Xcode app project and an iOS icon catalog."""
from __future__ import annotations
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def pbx(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(str(k)) + " = " + pbx(v, indent + 1) + ";\n" for k, v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (indent + 1) + pbx(v, indent + 1) + ",\n" for v in value) + "\t" * indent + ")"
    return json.dumps(str(value))


def generate():
    BUILD.mkdir(exist_ok=True)
    icon = ROOT / "Resources/RaindropIcon1024.png"
    if not icon.is_file():
        raise ValueError("Resources/RaindropIcon1024.png is required")
    png = icon.read_bytes()
    if png[:8] != b"\x89PNG\r\n\x1a\n" or int.from_bytes(png[16:20], "big") != 1024 or int.from_bytes(png[20:24], "big") != 1024:
        raise ValueError("The app icon must be a 1024×1024 PNG")
    if png[25] in (4, 6) or b"tRNS" in png:
        raise ValueError("The app icon must have no alpha channel or transparency")
    assets = BUILD / "Assets.xcassets"
    icon_set = assets / "AppIcon.appiconset"
    icon_set.mkdir(parents=True, exist_ok=True)
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    images = []
    specs = [*(('iphone', size, scale) for size in (20, 29, 40, 60) for scale in (2, 3)),
             *(('ipad', size, scale) for size in (20, 29, 40, 76) for scale in (1, 2)),
             ('ipad', 83.5, 2), ('ios-marketing', 1024, 1)]
    generated_sizes = {}
    for idiom, size, scale in specs:
        pixels = int(size * scale)
        filename = f"Icon-{pixels}.png"
        if pixels not in generated_sizes:
            subprocess.run(["sips", "-z", str(pixels), str(pixels), str(icon), "--out", str(icon_set / filename)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            generated_sizes[pixels] = filename
        images.append({"idiom": idiom, "size": f"{size}x{size}", "scale": f"{scale}x", "filename": filename})
    (icon_set / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    objects = {}
    def add(label, isa, **values):
        key = identifier(label)
        objects[key] = {"isa": isa, **values}
        return key
    main = add('main', 'PBXFileReference', lastKnownFileType='sourcecode.c.objc', path='../Sources/main.m', sourceTree='<group>')
    info = add('info', 'PBXFileReference', lastKnownFileType='text.plist.xml', path='../Resources/Info.plist', sourceTree='<group>')
    privacy = add('privacy', 'PBXFileReference', lastKnownFileType='text.xml', path='../Resources/PrivacyInfo.xcprivacy', sourceTree='<group>')
    game = add('game', 'PBXFileReference', lastKnownFileType='folder', path='../Resources/Game', sourceTree='<group>')
    art = add('assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
    product = add('product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex='0', path='ThirdDimension.app', sourceTree='BUILT_PRODUCTS_DIR')
    foundation = add('foundation', 'PBXFileReference', lastKnownFileType='wrapper.framework', path='System/Library/Frameworks/Foundation.framework', sourceTree='SDKROOT')
    uikit = add('uikit', 'PBXFileReference', lastKnownFileType='wrapper.framework', path='System/Library/Frameworks/UIKit.framework', sourceTree='SDKROOT')
    webkit = add('webkit', 'PBXFileReference', lastKnownFileType='wrapper.framework', path='System/Library/Frameworks/WebKit.framework', sourceTree='SDKROOT')
    source_phase = add('sources-phase', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=[add('main-build', 'PBXBuildFile', fileRef=main)], runOnlyForDeploymentPostprocessing='0')
    resource_phase = add('resources-phase', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=[add(name+'-build','PBXBuildFile',fileRef=value) for name,value in [('privacy',privacy),('game',game),('assets',art)]], runOnlyForDeploymentPostprocessing='0')
    framework_phase = add('frameworks-phase', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[add(name+'-build','PBXBuildFile',fileRef=value) for name,value in [('foundation',foundation),('uikit',uikit),('webkit',webkit)]], runOnlyForDeploymentPostprocessing='0')
    source_group = add('source-group','PBXGroup',children=[main,info,privacy,game,art],name='App',sourceTree='<group>')
    product_group = add('products','PBXGroup',children=[product],name='Products',sourceTree='<group>')
    framework_group = add('frameworks','PBXGroup',children=[foundation,uikit,webkit],name='Frameworks',sourceTree='<group>')
    main_group = add('root-group','PBXGroup',children=[source_group,framework_group,product_group],sourceTree='<group>')
    target_settings = {
        'PRODUCT_BUNDLE_IDENTIFIER':'com.billy.moonhop', 'PRODUCT_NAME':'ThirdDimension',
        'INFOPLIST_FILE':'../Resources/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO',
        'IPHONEOS_DEPLOYMENT_TARGET':'16.0', 'TARGETED_DEVICE_FAMILY':'1,2',
        'SDKROOT':'iphoneos', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
        'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon', 'CURRENT_PROJECT_VERSION':'4',
        'MARKETING_VERSION':'2.2', 'CLANG_ENABLE_OBJC_ARC':'YES', 'CLANG_ENABLE_MODULES':'YES',
        'GCC_C_LANGUAGE_STANDARD':'gnu17', 'CODE_SIGN_STYLE':'Automatic',
        'SUPPORTS_MACCATALYST':'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO',
        'OTHER_LDFLAGS':['$(inherited)','-Wl,-no_fixup_chains'],
        'GCC_WARN_ABOUT_RETURN_TYPE':'YES_ERROR', 'GCC_WARN_UNUSED_VARIABLE':'YES',
        'ENABLE_USER_SCRIPT_SANDBOXING':'YES', 'DEBUG_INFORMATION_FORMAT':'dwarf',
    }
    project_configs=[]; target_configs=[]
    for name in ('Debug','Release'):
        project_configs.append(add('project-'+name,'XCBuildConfiguration',name=name,buildSettings={'ALWAYS_SEARCH_USER_PATHS':'NO'}))
        settings={**target_settings,'GCC_OPTIMIZATION_LEVEL':'0' if name=='Debug' else 's'}
        target_configs.append(add('target-'+name,'XCBuildConfiguration',name=name,buildSettings=settings))
    project_list=add('project-configs','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
    target_list=add('target-configs','XCConfigurationList',buildConfigurations=target_configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
    target=add('target','PBXNativeTarget',buildConfigurationList=target_list,buildPhases=[source_phase,framework_phase,resource_phase],buildRules=[],dependencies=[],name='ThirdDimension',productName='ThirdDimension',productReference=product,productType='com.apple.product-type.application')
    project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2600'},buildConfigurationList=project_list,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=product_group,projectDirPath='',projectRoot='',targets=[target])
    directory=BUILD/'ThirdDimension.xcodeproj'
    directory.mkdir(exist_ok=True)
    (directory/'project.pbxproj').write_text('// !$*UTF8*$!\n'+pbx({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
    scheme=directory/'xcshareddata/xcschemes/ThirdDimension.xcscheme'
    scheme.parent.mkdir(parents=True,exist_ok=True)
    reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ThirdDimension.app" BlueprintName="ThirdDimension" ReferencedContainer="container:ThirdDimension.xcodeproj"/>'
    scheme.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2600" version="1.3">'
        '<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+reference+'</BuildActionEntry></BuildActionEntries></BuildAction>'
        '<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+reference+'</BuildableProductRunnable></LaunchAction>'
        '<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+reference+'</BuildableProductRunnable></ProfileAction>'
        '<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n')
    return directory


if __name__=='__main__':
    print(generate())
