#!/usr/bin/env python3
"""Package the built native executable, then check material IPA requirements."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import hashlib
import json
import os
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import wave
import zipfile
import zlib

root = Path(__file__).resolve().parents[1]
toolchain = Path(os.environ.get("MUSIC_TOOLCHAIN_ROOT", str(root.parent / "ios-toolchain")))
objdump_candidates = [shutil.which("llvm-objdump"),
                      toolchain / "usr/lib/llvm-20/bin/llvm-objdump",
                      toolchain / "root/usr/lib/llvm-20/bin/llvm-objdump"]
objdump = next((str(path) for path in objdump_candidates if path and Path(path).is_file()), None)
assert objdump, "LLVM tools missing; run Support/toolchain/bootstrap.py first"
layout_command = [sys.executable, str(root / "Support/verify_objc_layout.py"),
                  str(root / "Build/main.o"), "--objdump", objdump,
                  "--report", str(root / "Support/ABI-LAYOUT-REPORT.json")]
for controller in ("GMMusicShell", "GMSongsController", "GMAlbumsController", "GMPlaylistsController",
                   "GMSearchController", "GMSettingsController", "GMCompactPlayerView",
                   "GMPlaylistStore", "GMTrackEditsStore", "GMMetadataEditor", "GMTextEntryCell",
                   "GMCollectionDestinationPicker", "GMBrowseSongCell",
                   "GMPlaybackIndicatorView", "GMImportMenuButton", "GMArtworkBackdrop",
                   "GMArtworkPaletteState", "GMLyricsStore", "GMLyricsView", "GMLyricsEditor",
                   "GMAlbumImporter", "GMAlbumReviewController", "GMAlbumImportSession",
                   "GMAlbumImportEntry", "GMAlbumImportFieldCell", "GMPersonalizationStore",
                   "GMFontSettingsController", "GMIconPickerController", "GMPFontDraft",
                   "GMPFontPreviewController", "GMPIconChoiceTile", "GMPIconPreviewController",
                   "GMScrollAnimationView", "GMScrollRowDisplay", "GMScrollSettings",
                   "GMScrollPresetMenuButton", "GMScrollStyleCell", "GMScrollCreditsController",
                   "GMCDCaseView", "GMCDMotionHub", "GMCDCaseFallbackView", "GMCDScriptProxy",
                   "GMCDArtworkJob", "GMCDAlbumInspector", "GMCDCreditsController"):
    layout_command.extend(["--require-class", controller])
old_object = root / "Build/main-before-isa-fix.o"
if old_object.exists():
    layout_command.extend(["--before", str(old_object)])
subprocess.run(layout_command, check=True)
resource_info = plistlib.loads((root / "Resources" / "Info.plist").read_bytes())
app_version = resource_info["CFBundleShortVersionString"]
output = root.parent / "deliverables" / ("v" + app_version)
output.mkdir(parents=True, exist_ok=True)
app = root / "Build" / "Payload" / "Music.app"
if app.exists():
    # Rebuild this generated staging directory so removed resource versions
    # cannot remain in an otherwise fresh release IPA.
    shutil.rmtree(app)
app.mkdir(parents=True, exist_ok=True)
resource_files = []
for resource in sorted((root / "Resources").rglob("*")):
    assert not resource.is_symlink(), "Bundle resources must be ordinary files/directories"
    if resource.is_file():
        relative = resource.relative_to(root / "Resources")
        assert "__pycache__" not in relative.parts and resource.suffix not in (".pyc", ".pyo")
        target = app / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(resource, target)
        resource_files.append(relative)
shutil.copy2(root / "Build" / "GlassMusic", app / "GlassMusic")
(app / "GlassMusic").chmod(0o755)

binary = (app / "GlassMusic").read_bytes()
magic, cputype, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<8I",binary)
assert magic == 0xfeedfacf and cputype == 0x100000c and filetype == 2
assert flags & 0x200000 # Position-independent executable.
offset = 32
libraries = []
signature = None
entry = None
platform = None
for _ in range(ncmds):
    command, size = struct.unpack_from("<II",binary,offset)
    assert size >= 8 and offset + size <= 32 + sizeofcmds
    if command == 0xc:
        name_offset = struct.unpack_from("<I",binary,offset+8)[0]
        name = binary[offset+name_offset:offset+size].split(b"\0")[0].decode()
        libraries.append(name)
        assert name.startswith(("/System/Library/Frameworks/","/usr/lib/"))
    elif command == 0x32:
        platform, minimum, sdk = struct.unpack_from("<III",binary,offset+8)
        assert platform == 2 and minimum == (16 << 16) and sdk == (26 << 16)
    elif command == 0x80000028:
        entry = struct.unpack_from("<Q",binary,offset+8)[0]
        assert 0 < entry < len(binary)
    elif command == 0x2c:
        assert struct.unpack_from("<I",binary,offset+16)[0] == 0 # Unencrypted.
    elif command == 0x1d:
        sig_offset, sig_size = struct.unpack_from("<II",binary,offset+8)
        signature = binary[sig_offset:sig_offset+sig_size]
        assert len(signature) == sig_size
    offset += size
assert platform == 2 and entry and signature and len(libraries) >= 8
assert "/System/Library/Frameworks/AVKit.framework/AVKit" in libraries
assert "/System/Library/Frameworks/CoreText.framework/CoreText" in libraries
assert "/System/Library/Frameworks/WebKit.framework/WebKit" in libraries
assert "/System/Library/Frameworks/CoreMotion.framework/CoreMotion" in libraries

# Check the ad-hoc CodeDirectory and every SHA-256 code-page hash.
magic, sig_length, count = struct.unpack_from(">III",signature)
assert magic == 0xfade0cc0 and sig_length <= len(signature)
verified_pages = 0
for index in range(count):
    slot, blob_offset = struct.unpack_from(">II",signature,12+index*8)
    blob_magic, blob_length = struct.unpack_from(">II",signature,blob_offset)
    if blob_magic != 0xfade0c02:
        continue
    cd = signature[blob_offset:blob_offset+blob_length]
    _, _, cd_version, cd_flags, hash_offset, ident_offset, special_slots, code_slots, code_limit = struct.unpack_from(">9I",cd)
    hash_size, hash_type, platform_id, page_exp = struct.unpack_from(">4B",cd,36)
    assert cd_flags & 2 and hash_type == 2 and hash_size == 32
    assert code_limit <= len(binary) and code_slots > 0
    page_size = 1 << page_exp
    for page in range(code_slots):
        digest = hashlib.sha256(binary[page*page_size:min((page+1)*page_size,code_limit)]).digest()
        assert digest == cd[hash_offset+page*hash_size:hash_offset+(page+1)*hash_size]
    verified_pages += code_slots
assert verified_pages > 0

info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleExecutable"] == "GlassMusic"
assert info["CFBundleIdentifier"] == "com.billy.glassmusic"
assert info["CFBundleDisplayName"] == "Music" and info["CFBundleName"] == "Music"
assert "audio" in info["UIBackgroundModes"]
assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
scene = info["UIApplicationSceneManifest"]["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"][0]
assert scene["UISceneDelegateClassName"] == "SceneDelegate"
assert b"SceneDelegate" in binary and b"AppDelegate" in binary

# Validate every declared icon family at both device-specific sizes, including
# the 1024px picker/export previews. The resources are intentionally opaque RGB
# PNGs; iOS supplies the Home Screen mask. No image library is needed here.
def verify_opaque_png(path, side):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path.name
    cursor = 8
    image_data = bytearray()
    header_seen = False
    end_seen = False
    while cursor < len(data):
        assert cursor + 12 <= len(data), path.name
        length = struct.unpack_from(">I", data, cursor)[0]
        chunk_type = data[cursor+4:cursor+8]
        chunk_end = cursor + 12 + length
        assert chunk_end <= len(data), path.name
        chunk = data[cursor+8:cursor+8+length]
        checksum = struct.unpack_from(">I", data, cursor+8+length)[0]
        assert zlib.crc32(chunk_type + chunk) & 0xffffffff == checksum, path.name
        if chunk_type == b"IHDR":
            assert not header_seen and cursor == 8 and length == 13, path.name
            assert struct.unpack(">IIBBBBB", chunk) == (side, side, 8, 2, 0, 0, 0), path.name
            header_seen = True
        elif chunk_type == b"IDAT":
            assert header_seen and not end_seen, path.name
            image_data.extend(chunk)
        elif chunk_type == b"tRNS":
            raise AssertionError(f"Icon must be opaque: {path.name}")
        elif chunk_type == b"IEND":
            assert length == 0 and chunk_end == len(data), path.name
            end_seen = True
        cursor = chunk_end
    assert header_seen and end_seen and image_data, path.name
    row_bytes = 1 + side * 3
    expected_bytes = row_bytes * side
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(image_data, expected_bytes + 1)
    assert decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data, path.name
    assert len(pixels) == expected_bytes, path.name
    assert all(pixels[row * row_bytes] <= 4 for row in range(side)), path.name

alternate_icon_names = ("Noir", "Ivory", "Aurora", "Signal", "Chrome")
icon_families = {"Primary": "AppIcon"}
icon_families.update({name: "Icon" + name for name in alternate_icon_names})
for key, sizes in (
    ("CFBundleIcons", ("60x60", "40x40", "29x29", "20x20")),
    ("CFBundleIcons~ipad", ("76x76", "83.5x83.5", "40x40", "29x29", "20x20")),
):
    declarations = info[key]
    assert set(declarations["CFBundleAlternateIcons"]) == set(alternate_icon_names)
    for name, prefix in icon_families.items():
        record = declarations["CFBundlePrimaryIcon"] if name == "Primary" else declarations["CFBundleAlternateIcons"][name]
        assert record["CFBundleIconFiles"] == [prefix + size for size in sizes]

icon_size_scales = (("20x20", (1, 2, 3)), ("29x29", (1, 2, 3)),
                    ("40x40", (1, 2, 3)), ("60x60", (2, 3)),
                    ("76x76", (1, 2)), ("83.5x83.5", (2,)))
icon_asset_names = []
for name, prefix in icon_families.items():
    for size, scales in icon_size_scales:
        for scale in scales:
            suffix = "" if scale == 1 else f"@{scale}x"
            filename = f"{prefix}{size}{suffix}.png"
            side = round(float(size.split("x")[0]) * scale)
            verify_opaque_png(app / filename, side)
            icon_asset_names.append(filename)
    preview = "AppIcon1024.png" if name == "Primary" else f"{prefix}Preview.png"
    verify_opaque_png(app / preview, 1024)
    icon_asset_names.append(preview)

privacy = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
assert not privacy["NSPrivacyTracking"] and not privacy["NSPrivacyCollectedDataTypes"]
# The complete upstream license must accompany the binary adaptation. Match
# the pinned original bytes, then also verify the archived resources below.
cask_license = (app / "Cask3-LICENSE.txt").read_bytes()
assert hashlib.sha256(cask_license).hexdigest() == "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"
assert cask_license == (root / "Support/Upstream/Cask3/LICENSE").read_bytes()
cask_notice = (app / "Cask3-ACKNOWLEDGMENTS.txt").read_bytes()
assert b"Ryan Nair" in cask_notice and b"Ryan Petrich" in cask_notice
assert b"f82e252334d69a151afa8f20db3d59e7a84ee592" in cask_notice
cask_source = (root / "Support/Upstream/Cask3/Sources/Cask.swift").read_bytes()
assert hashlib.sha256(cask_source).hexdigest() == "dd90c1036bdf7218b83afcc3a7d66ce4fbd381b64aec55c77ab5a2e2118fc8de"

# The CD renderer is a fully bundled local resource tree. Its build manifest
# ties the shipped JavaScript to every editable source and vendored input.
cd_root = app / "CDCase"
for filename in ("index.html", "music-cd.js", "manifest.json"):
    assert (cd_root / filename).is_file() and (cd_root / filename).stat().st_size, filename
for filename in ("CDCase-ACKNOWLEDGMENTS.txt", "Three-LICENSE.txt"):
    assert (app / filename).is_file() and (app / filename).stat().st_size, filename
cd_manifest = json.loads((cd_root / "manifest.json").read_text())
assert cd_manifest["schema"] == 1
assert cd_manifest["upstreamCommit"] == "efba8dfb956cca848422f18e8ede1bdf96033fca"
assert cd_manifest["threeVersion"] == "0.185.1" and cd_manifest["esbuildVersion"] == "0.25.12"
assert cd_manifest["output"]["path"] == "Resources/CDCase/music-cd.js"
cd_bundle_digest = hashlib.sha256((cd_root / "music-cd.js").read_bytes()).hexdigest()
assert cd_bundle_digest == cd_manifest["output"]["sha256"], "CD renderer bundle hash mismatch"
required_cd_inputs = {"Sources/CDCaseJS/" + name for name in (
    "stage.js", "caseGeometry.js", "shaders.js", "bridge.js", "vendor/three.core.js",
    "vendor/three.module.js", "vendor/LICENSE", "vendor/PROVENANCE.json")}
required_cd_inputs.add("Support/build_cd_renderer.mjs")
assert required_cd_inputs.issubset(cd_manifest["inputs"]), "CD renderer input manifest is incomplete"
for name, digest in cd_manifest["inputs"].items():
    relative = Path(name)
    assert not relative.is_absolute() and ".." not in relative.parts, name
    path = (root / relative).resolve()
    assert path.is_relative_to(root) and path.is_file(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, "Stale CD renderer input: " + name

upstream_root = root / "Support/Upstream/CDCase"
cd_upstream = json.loads((upstream_root / "PROVENANCE.json").read_text())
assert cd_upstream["commit"] == cd_manifest["upstreamCommit"]
assert cd_upstream["repository"] == "https://github.com/annnguyentt/vibe-coding"
assert cd_upstream["files"], "Missing original CD case sources"
for record in cd_upstream["files"]:
    relative = Path(record["path"])
    assert not relative.is_absolute() and ".." not in relative.parts
    path = (upstream_root / relative).resolve()
    assert path.is_relative_to(upstream_root) and path.is_file()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == record["sha256"], relative
three_root = root / "Sources/CDCaseJS/vendor"
three_provenance = json.loads((three_root / "PROVENANCE.json").read_text())
assert three_provenance["version"] == cd_manifest["threeVersion"]
assert {"three.core.js", "three.module.js", "LICENSE"}.issubset(three_provenance["files"])
for name, digest in three_provenance["files"].items():
    relative = Path(name)
    assert not relative.is_absolute() and ".." not in relative.parts
    path = (three_root / relative).resolve()
    assert path.is_relative_to(three_root) and path.is_file()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, relative
assert (app / "Three-LICENSE.txt").read_bytes() == (three_root / "LICENSE").read_bytes()

class CDLocalDependencies(HTMLParser):
    def __init__(self):
        super().__init__()
        self.scripts = []

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        assert tag != "base", "CD renderer must retain its local document base"
        attribute = "href" if tag == "link" else "src"
        if tag not in ("script", "link", "img", "source", "audio", "video", "iframe") or attribute not in attributes:
            return
        location = urlsplit(attributes[attribute])
        if location.scheme == "data" and tag in ("img", "source", "audio", "video"):
            return
        assert not location.scheme and not location.netloc, "External CD renderer dependency"
        relative = Path(unquote(location.path))
        assert not relative.is_absolute(), "Absolute CD renderer dependency"
        target = (cd_root / relative).resolve()
        assert target.is_relative_to(cd_root) and target.is_file(), relative
        if tag == "script":
            self.scripts.append(target)

cd_html = CDLocalDependencies()
cd_html.feed((cd_root / "index.html").read_text())
assert (cd_root / "music-cd.js").resolve() in cd_html.scripts, "CD renderer entry script is missing"
cd_render_report = json.loads((root / "Support/CD-RENDER-REPORT.json").read_text())
assert cd_render_report.get("passed") is True, "CD renderer validation did not pass"
assert cd_render_report.get("renderBundleSHA256") == cd_bundle_digest, "Renderer validation is for a different bundle"


with wave.open(str(app / "Glass-Study.wav"),"rb") as audio:
    duration = audio.getnframes() / audio.getframerate()
    assert duration == 20 and audio.getnchannels() == 2

ipa = output / "Music.ipa"
with zipfile.ZipFile(ipa,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    # Archive this app explicitly. A previous GlassMusic.app staging directory
    # may still exist beside it and must never become a second IPA payload.
    for path in sorted(app.rglob("*")):
        if path.is_file():
            archive.write(path,path.relative_to(root / "Build"))
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    assert all(name.startswith("Payload/Music.app/") for name in archive.namelist())
    entry_info = archive.getinfo("Payload/Music.app/GlassMusic")
    assert entry_info.external_attr >> 16 & stat.S_IXUSR
    assert archive.read("Payload/Music.app/GlassMusic") == binary
    for relative in resource_files:
        assert archive.read("Payload/Music.app/" + relative.as_posix()) == (root / "Resources" / relative).read_bytes(), relative
    for filename in icon_asset_names:
        assert archive.read("Payload/Music.app/" + filename) == (app / filename).read_bytes()
    assert archive.read("Payload/Music.app/Cask3-LICENSE.txt") == cask_license
    assert archive.read("Payload/Music.app/Cask3-ACKNOWLEDGMENTS.txt") == cask_notice
    assert not any(".." in Path(name).parts for name in archive.namelist())

report = {
    "app":"Music", "version":app_version, "build":info["CFBundleVersion"], "architecture":"arm64",
    "bundle_identifier":info["CFBundleIdentifier"], "bundle_path":"Payload/Music.app",
    "executable":info["CFBundleExecutable"],
    "platform":"iOS device", "minimum_ios":"16.0", "linked_sdk":"26.0", "binary_bytes":len(binary),
    "ipa_bytes":ipa.stat().st_size, "sha256":hashlib.sha256(ipa.read_bytes()).hexdigest(),
    "code_signature":"ad-hoc; installer must re-sign for the user",
    "signature_code_pages_verified":verified_pages, "frameworks":libraries,
    "demo_seconds":duration,"zip_integrity":"passed",
    "cd_case_resources":{"entry":"CDCase/index.html", "bundle":"CDCase/music-cd.js",
                         "bundle_sha256":cd_bundle_digest, "three_version":cd_manifest["threeVersion"],
                         "esbuild_version":cd_manifest["esbuildVersion"], "upstream_commit":cd_manifest["upstreamCommit"],
                         "verified_inputs":len(cd_manifest["inputs"]), "verified_originals":len(cd_upstream["files"]),
                         "dependency_check":"Local HTML dependencies, renderer input/output hashes, original upstream/vendor hashes, and every archived resource byte verified",
                         "runtime":"Bundled local WebKit renderer; no CDN or package registry access is required by the app"},
    "cd_case_behavior":{"classes":["GMCDCaseView","GMCDMotionHub","GMCDCaseFallbackView","GMCDScriptProxy","GMCDArtworkJob","GMCDAlbumInspector","GMCDCreditsController"],
                        "albums":"Existing two-column native grid; tap opens songs, long press opens inspector and continues native drag tilt",
                        "inspector":"Native glass controls, separate tilt and browse gesture regions, album flip, open/close lid, landscape layout and Play Album",
                        "now_playing":"Current song artwork printed on spinning disc; playback follows actual player state; native artwork spring, lyrics swap and zoom source retained",
                        "motion":"One CMMotionManager, private serial queue, relative attitude, orientation baseline reset, coalesced main-thread updates",
                        "budgets":{"live_grid_cases":4,"live_hero_cases":1,"grid_room_map":128,"hero_room_map":256,"grid_pixel_ratio_max":1,"hero_pixel_ratio_max":1.5,"grid_fps_max":18,"hero_fps_max":30,"motion_hz_max":30,"grid_art_pixels_max":512,"hero_art_pixels_max":1024},
                        "visibility":"Owner-visible, foreground-active scene/window intersection required; row reuse, navigation, modal, lyrics and app/scene deactivation release renderer demand",
                        "fallback":"Native static clear-case presentation with current circular artwork, or an available matching rendered still; failed WebGL does not remove library access",
                        "accessibility":"Native action alternatives; automatic spin/motion suppressed for Reduce Motion or Prefer Cross-Fade; explicit lid changes settle without added motion",
                        "offline":"Only a bundled file page, IIFE Three bundle and locally encoded art; nonpersistent WebKit store; CSP rejects network content and navigation is restricted to the bundled CDCase directory",
                        "render_check":"Support/CD-RENDER-REPORT.json records actual Chromium/SwiftShader checks; no WebKit-on-iPhone execution claimed"},
    "compile_and_link":"passed", "object_layout_regression_check":"passed", "device_or_simulator_testing":"not available",
    "runtime_api_validation":"narrow Foundation/UIKit/AVKit/AVFAudio/PhotosUI/ImageIO/QuartzCore/CoreText/WebKit/CoreMotion declarations checked against public documentation and SDK headers; no device run here",
    "interface":{"tabs":["Songs","Albums","Playlists","Search","Settings"], "tab_controller":"UITabBarController",
                 "ios26_mini_player":"Permanent native UITabAccessory, resolved dynamically, with one persistent compact-player content view",
                 "native_dock":{"class":"UITabBarController", "availability":"Native accessory and minimization on supported iOS 26 layouts",
                                 "tabs":["Songs","Albums","Playlists","Search","Settings"],
                                 "navigation":"Existing viewControllers/UITabBarItem model and five UINavigationController stacks",
                                 "selection":"UIKit's genuine tab bar and selected capsule remain active in every state",
                                 "minimize_behavior":"UITabBarMinimizeBehaviorOnScrollDown (2); UIKit owns collapse and reverse-scroll expansion",
                                 "compact_navigation":"UIKit decides the selected-tab compact layout; no forced Songs/Settings pair or disguised search tab",
                                 "scroll_registration":"Browse controllers explicitly register their table with setContentScrollView:forEdge:NSDirectionalRectEdgeAll",
                                 "accessory_environment":"Dynamic UITraitTabAccessoryEnvironment registration with a public no-argument action; initial/window/layout checks also update regular/inline content",
                                 "geometry":"Native bar/accessory control outer size, position, selection bubble, and transition; no custom dock, hidden-bar swap, or fixed 140-point reservation",
                                 "foreground":"Same live title, artwork, and transport content throughout the native accessory transition; skip is hidden inline",
                                 "content_points":{"intrinsic_height":52, "regular_artwork":30, "inline_artwork":26, "title":14, "artist":11, "transport_frame":30, "transport_hit_area":44, "play_symbol":13, "next_symbol":12}},
                 "now_playing":"Full-screen; guarded native zoom from the mini-player on iOS 18+, cross-dissolve fallback; lower close control",
                 "now_playing_controls":["Lyrics", "Native AVRoutePickerView AirPlay", "Playback mode"],
                 "playback_controls":"Plain transport glyphs above shared glass retain the 0.5 nested-backplate correction and the 0.4 play/pause symbol-state correction",
                 "playback_indicator":"Four accent bars in current-song rows; Core Animation keyframes while playing, shorter static bars when paused; Reduce Motion is static, off-window/reused indicators stop; no per-cell timers",
                 "native_glass":"UIKit supplies the genuine tab bar, selection bubble, and accessory glass; row actions retain native UIGlassEffect/UIGlassContainerEffect; glass views and ancestors retain alpha 1",
                 "native_buttons":"Native glass action surfaces where available; plain foreground transport glyphs above shared mini-player glass",
                 "older_ios_fallback":"Regular system tabs, 52-point blur mini-player, and compatible row controls; 64-point extra bottom inset only when native UITabAccessory is unavailable",
                 "import_menu":{"class":"GMImportMenuButton", "anchor":"The actual plus UIButton in a custom UIBarButtonItem",
                                "presentation":"Native UIButton.menu/showsMenuAsPrimaryAction with one native glass surface; no import-choice bottom sheet",
                                "choices":["Import Songs","Import Album"],
                                "handoff":"UIControl willEnd native animator completion precedes the existing import routes; pending choice, generation, window, and busy checks protect repeated actions"},
                 "row_actions":"Songs and playlists reveal trash and More from the right; native glass follows the drag, merges/separates, and settles with an interruptible spring; foreground gray fill and only its right corners follow reveal progress; UIKit selection flash suppressed",
                 "song_row_selection":"Starts playback in the current list without opening Now Playing; Play/Shuffle header actions still present the full player; Search preserves query/results and resigns its keyboard",
                 "destructive_actions":"Song deletion, playlist deletion, and playlist membership removal require confirmation",
                 "background_gradient":"Dynamic mode shares the current artwork palette throughout Music; System/Light/Dark retain their standard backgrounds; Now Playing retains artwork color flow",
                 "settings":["System/Dark/Light/Dynamic appearance", "Font", "App Icon", "Scrolling Animations switch", "Animation Style picker and preview", "Full native accent color picker", "Import Songs", "Import Album", "Library counts", "Version"],
                 "dynamic_theme":{"stored_mode":3, "uikit_style":0, "contrast":"System light/dark semantic foregrounds", "migration":"Previous Gray value 3 now selects Dynamic"}},
    "library":{"songs":"Dedicated full alphabetical song list with Play and Shuffle header actions",
               "albums":"Grouped by album and album artist; disc/track ordering; album browser has no All Songs shortcut",
               "playlists":"Local Documents/MusicPlaylists.plist; stable UUIDs, ordered filename identifiers, custom artwork, atomic writes",
               "search":"Local songs, artists, and albums",
               "playback_queue":"Stable track identifiers retain natural collection order and active playback order across library changes",
               "audio_directory":"Documents/Music"},
    "playback_modes":{"cycle":["Off", "Shuffle", "Repeat One", "Off"],
                      "shuffle":"Fisher-Yates permutation of the current collection; header Shuffle selects a random first song",
                      "repeat_one":"AVAudioPlayer.numberOfLoops=-1; other modes use zero",
                      "headers":"Play selects normal order; Shuffle selects shuffle mode",
                      "song_rows":"Preserve the current mode"},
    "artwork_presentation":{"foreground":"GMCDCaseView with original case refraction shaders and current song art printed on disc", "class":"GMArtworkBackdrop", "shared_palette_class":"GMArtworkPaletteState",
                            "paused_scale":0.90, "playing_scale":1.0,
                            "scale_motion":"Interruptible .50-second spring, damping ratio .76; bypassed for Reduce Motion, Prefer Cross-Fade, offscreen, or lyrics presentation",
                            "analysis":"One shared local 40x40 RGBA extraction for the current artwork object; alpha-aware dominant palette on a background queue; generation check before main-queue publication to every backdrop",
                            "background":"Axial base and three broad radial gradient layers blend from current presentation colors/positions; accent fallback without artwork; shared light/dark source-tone bounds support semantic text contrast",
                            "continuous_processing":"Palette analysis runs only when artwork changes; visible CD renderers have bounded foreground animation loops, with no remote artwork fetch",
                            "focused_algorithm_checks":"The retained pure C extractor passed transparent/bounded input, monochrome, dominant ordering, premultiplied alpha, and white/black checks under AddressSanitizer/UndefinedBehaviorSanitizer in 0.7; shared UIKit publication/rendering still requires a device check"},
    "album_import":{"classes":["GMAlbumImporter", "GMAlbumReviewController", "GMAlbumImportSession", "GMAlbumImportEntry", "GMAlbumImportFieldCell"],
                    "selection":["Album Folder", "Select Album Songs"],
                    "review":"Draft album name, artist, cover, and ordered songs; Save imports, Cancel discards the draft",
                    "source_access":"Security-scoped coordinated reads; recursive streamed folder enumeration skips hidden items, packages, symlinks, and nonregular files",
                    "limits":{"visited_entries":4096, "directory_depth":8, "songs":500, "batch_bytes":8589934592, "song_bytes":2147483648, "cover_source_bytes":33554432},
                    "artwork":"Prefer cover/front/folder-named folder images, then embedded artwork; editable from Files; bounded 1200-pixel decode and 3 MiB JPEG save; shared cover avoids per-song duplicate decode",
                    "staging":"Caches/AlbumImports/<UUID>",
                    "audio_names":"Unique Album-UUID-ordinal.ext copies in Documents/Music",
                    "metadata":"One MusicEdits.plist commit applies album, artist, albumArtist, title/order fields and a shared cover; optional discNumber/trackNumber retain formatVersion 1",
                    "failure":"Observed move or metadata failures remove only the newly published copies; cleanup failures are reported; original sources remain unchanged",
                    "atomicity_limit":"The metadata manifest is atomic; the whole set of audio moves is not a crash-atomic filesystem transaction"},
    "icons":{"primary":"Original white/red note", "alternates":list(alternate_icon_names),
             "declarations":["CFBundleIcons", "CFBundleIcons~ipad"],
             "validated_png_resources":len(icon_asset_names), "validation":"Required dimensions, opaque RGB PNG headers, chunk CRCs, complete image data, and final archive bytes checked",
             "preview_pixels":1024,
             "generation":"Support/create_icons.py regenerates the five alternate families using Pillow primitives",
             "custom_image":"Saved/previewed/exported for a manually configured Home Screen Shortcut; public setAlternateIconName only selects bundle-declared icons"},
    "personalization":{"classes":["GMPersonalizationStore", "GMFontSettingsController", "GMIconPickerController",
                                    "GMPFontDraft", "GMPFontPreviewController", "GMPIconChoiceTile", "GMPIconPreviewController"],
                       "font_choices":["System Default", "Native installed-font picker", "Import TTF/OTF from Files"],
                       "font_preview":"Save/Cancel draft; final UUID font path exists before registration and is not moved while registered",
                       "font_registration":"CoreText process scope; saved font files register again at launch; unavailable selection falls back to system",
                       "font_application":"App text and navigation/button titles; monospaced elapsed/duration counters retain their baseline",
                       "limits":{"font_bytes":16777216, "saved_font_files":32, "icon_import_bytes":12582912, "saved_icon_bytes":6291456, "manifest_bytes":131072},
                       "manifest":"Documents/MusicPersonalization/Personalization.plist",
                       "files":["Documents/MusicPersonalization/Fonts/<UUID>.ttf|otf", "Documents/MusicPersonalization/Icons/<UUID>.png"],
                       "persistence":"Bounded reads and complete manifest validation; atomic commit precedes persistent selection changes; corrupt manifest blocks writes; failed custom-image commit removes only the new image",
                       "picker_handoff":"Font/image Files results wait for document-picker dismissal before presenting a preview or error",
                       "alternate_icon_result":"Bundle-declared request; completion handled on main queue and checked against actual alternateIconName; unavailable host changes report an error",
                       "custom_icon":"Bounded image decode then opaque 1024-pixel square, saved independently of the active bundled icon; export through UIActivityViewController",
                       "shortcut":"Manual Copy Launch URL from LiveContainer with URL/Open URLs actions; Open App for a separately installed Music copy",
                       "review":"Read-only transaction, ownership, public ABI, and callback review; no device execution"},
    "lyrics":{"classes":["GMLyricsStore", "GMLyricsView", "GMLyricsEditor"],
              "controls":"Lyrics panel with Add Lyrics from Files and Paste or Write; native Save/Cancel editor captures the stable song identifier",
              "formats":[".txt", ".lrc"], "encoding":"UTF-8 or UTF-16",
              "display":"Plain selectable scrollable text; recognized LRC timestamps/metadata stripped while section labels remain; no timed synchronization",
              "storage":"Documents/MusicLyrics.plist; formatVersion 1; lyrics dictionary keyed by stable song identifiers",
              "persistence":"Atomic save before publishing memory changes; failed/corrupt loads block writes; blank Save removes that song's lyrics",
              "limits":{"import_bytes":262144, "text_utf16_units":65536, "manifest_bytes":8388608, "song_identifiers":20000},
              "network":"No lyric lookup or app network client; a system Files provider can download cloud-only selections"},
    "editing":{"song_details":"Independent title, artist, and album overrides keyed by stable track identifiers; audio filenames and embedded tags remain unchanged",
               "artwork_selection":"Photos or Files artwork stays in the editor draft until Save",
               "album_assignment":"Add to Album preserves title and copies target album, artist, albumArtist, and artwork; clears the previous cover if target has none",
               "playlist_actions":"Edit playlist name/custom artwork; Add to Playlist changes membership without moving the audio file",
               "song_manifest":"Documents/MusicEdits.plist",
               "artwork_directories":["Documents/MusicEditsArtwork", "Documents/MusicPlaylistArtwork"],
               "persistence":"UUID JPEGs up to 1200 pixels per side and 3 MiB; bounded ImageIO reads; atomic manifests; failed saves preserve original data; corrupt manifests block writes"},
    "deletion":{"imported_song":"Trash from any song row removes the app's local audio copy globally, while preserving the original import source",
                "playlist_membership":"Remove from Playlist in More removes membership only",
                "playlist":"Deleting a playlist preserves its songs",
                "demo":"The bundled demo is hidden persistently without modifying the signed app bundle"},
    "scrolling_animations":{"classes":["GMScrollAnimationView", "GMScrollSettings", "GMScrollStyleCell", "GMScrollCreditsController"],
                            "source":"https://github.com/ryannair05/Cask-3", "source_commit":"f82e252334d69a151afa8f20db3d59e7a84ee592",
                            "credits":{"cask3":"Ryan Nair (@ryannair05)", "original_cask":"Ryan Petrich"},
                            "license":"Apache-2.0; complete upstream bytes included in IPA and source; offline acknowledgments UI",
                            "preset_count":15, "presets":["Fade", "Flip", "Bounce", "Color", "Permanent Color", "Glitch", "Helix", "Rotate", "Zoom", "Drop", "Stretch", "Slide", "Shake", "Swing", "Jiggle"],
                            "default":{"enabled":False, "preset":"fade"}, "duration_seconds":0.5,
                            "settings":"Switch in the normal Settings page; Animation Style has an anchored native UIButton/UIMenu chooser and inline preview/replay; no new tab",
                            "manifest":"Documents/MusicScrollSettings.plist; independent versioned atomic preference file",
                            "scope":"Opted-in app-owned content in Music library table rows; no global UIKit hooks, injection, or private table selectors",
                            "isolation":"Existing swipe foreground and native glass action tray remain outside the animated row-content host; native tab bar/accessory code preserved",
                            "motion_accessibility":"Added scroll animations respect iOS Reduce Motion",
                            "corrections":"Rotate uses scalar radians for a complete turn; Shake has matching value/timing counts; spring/color effects adapted for readable content",
                            "runtime_validation":"Compile, static ownership/API review, and package verification only; no iOS device or simulator available"},
    "device_validation":{"baseline":"Music 0.10 / build 11 recovered from the saved source; existing dock/Cask/playback data model retained",
                         "latest_user_request":"Clear CD cases in the album grid and Now Playing; local artwork on spinning discs; motion tilt and an opening album inspector",
                         "current_build":f"{app_version} / build {info['CFBundleVersion']}: native compile/ABI/link/signature/package checks and browser renderer checks only; no iPhone or simulator execution",
                         "device_checks_remaining":["LiveContainer launch and existing library retention", "WKWebView file loading and GPU behavior", "foreground/background/lyrics and row reuse", "device-motion orientation calibration", "long press continuation and native glass controls", "portrait/landscape inspector", "energy and thermal behavior with a large library"]},
    "startup_fix":"NSObject root header reserves its 8-byte isa pointer; corrected constant offsets in SceneDelegate and GMTrack verified in disassembly"
}
(root / "BUILD-REPORT.json").write_text(json.dumps(report,indent=2)+"\n")
source = output / "Music-Source.zip"
source_files = []
with zipfile.ZipFile(source,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for folder in ("Sources","Resources","Support"):
        for path in sorted((root/folder).rglob("*")):
            relative = path.relative_to(root)
            if "__pycache__" in relative.parts or path.suffix in (".pyc", ".pyo"):
                continue
            assert not path.is_symlink(), "Source archive must not follow external symlinks"
            if path.is_file():
                archive.write(path,Path("Music")/relative)
                source_files.append(relative)
    for name in ("README.txt","build-macos.sh","BUILD-REPORT.json"):
        archive.write(root/name,Path("Music")/name)
with zipfile.ZipFile(source) as archive:
    assert archive.testzip() is None
    assert not any("__pycache__" in Path(name).parts or name.endswith((".pyc", ".pyo")) for name in archive.namelist())
    for relative in source_files:
        assert archive.read("Music/" + relative.as_posix()) == (root / relative).read_bytes(), relative
    for name in required_cd_inputs:
        assert "Music/" + name in archive.namelist(), name
    for name in ("bootstrap.py", "build_linux.py", "make_sdk.py", "capture_imports.py", "symbols.json", "ubuntu-packages.json", "README.txt"):
        assert "Music/Support/toolchain/" + name in archive.namelist(), name
    for record in cd_upstream["files"]:
        assert "Music/Support/Upstream/CDCase/" + record["path"] in archive.namelist(), record["path"]
print(json.dumps({"ipa":str(ipa),"source":str(source),"verification":report},indent=2))
