#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Apply reviewed overlays to the exact engine revision in build.sh. Fail on drift."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import sys

ROOT = Path(sys.argv[1]).resolve()
OVERLAY = Path(__file__).resolve().parent


def change(path, old, new, count=1):
    file = ROOT / path
    text = file.read_text()
    found = text.count(old)
    if found != count:
        raise RuntimeError(f'{path}: expected {count} matches, found {found}: {old[:100]!r}')
    file.write_text(text.replace(old, new))


def append(path, content):
    with (ROOT / path).open('a') as handle:
        handle.write('\n' + content + '\n')


project = ROOT / 'Palladium.xcodeproj/project.pbxproj'
if 'PBXFileSystemSynchronizedRootGroup' not in project.read_text():
    raise RuntimeError('The pinned project no longer auto-includes source files.')

# Keep runtime symbols and internal preference keys stable; brand only app identity.
for folder in ['Palladium', 'ShareExtension', 'Palladium.xcodeproj']:
    for path in (ROOT / folder).rglob('*'):
        if path.is_file() and path.suffix in {'.swift', '.plist', '.entitlements', '.pbxproj'}:
            text = path.read_text()
            text = text.replace('com.tfourj.Palladium', 'com.strezzy.glint').replace('com.tfourj.palladium', 'com.strezzy.glint')
            text = text.replace('"palladium"', '"glint"').replace('palladium://', 'glint://')
            text = text.replace('<string>palladium</string>', '<string>glint</string>')
            # The legacy patched-IPA helper must not fetch a different app's release.
            text = text.replace('https://api.github.com/repos/tfourj/Palladium/releases/latest',
                'https://api.github.com/repos/Strezzy/ios-apps/releases/tags/' + os.environ.get('GLINT_TAG', 'glint-0.1.0-build1'))
            path.write_text(text)

text = project.read_text()
text = re.sub(r'ASSETCATALOG_COMPILER_APPICON_NAME = [^;]+;', 'ASSETCATALOG_COMPILER_APPICON_NAME = GlintIcon;', text)
text = re.sub(r'INFOPLIST_KEY_CFBundleDisplayName = [^;]+;', 'INFOPLIST_KEY_CFBundleDisplayName = Glint;', text)
project.write_text(text)
for path in [ROOT / 'Palladium/Info.plist', ROOT / 'ShareExtension/Info.plist']:
    data = plistlib.loads(path.read_bytes())
    data['CFBundleDisplayName'] = 'Glint'
    if path.parent.name == 'Palladium':
        data['NSPhotoLibraryAddUsageDescription'] = 'Glint adds videos to Photos only when you choose Save to Photos.'
        data['UIFileSharingEnabled'] = True
        data['LSSupportsOpeningDocumentsInPlace'] = True
    path.write_bytes(plistlib.dumps(data))

assets = ROOT / 'Palladium/Resources/Assets.xcassets'
assets.mkdir(parents=True, exist_ok=True)
accent = assets / 'AccentColor.colorset/Contents.json'
accent.write_text(json.dumps({'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.94','green':'0.36','blue':'0.16','alpha':'1.0'}}}],'info':{'author':'xcode','version':1}}))
strings = ROOT / 'Palladium/Resources/Localizable.xcstrings'
text = strings.read_text().replace('"value" : "Palladium"', '"value" : "Glint"').replace('"value": "Palladium"', '"value": "Glint"')
strings.write_text(text)
for name in ['GlintDesign.swift', 'GlintMedia.swift', 'GlintQuality.swift', 'GlintPaste.swift', 'GlintPlayback.swift', 'GlintOrigin.swift', 'GlintBrowser.swift', 'GlintBrowserScript.swift']:
    shutil.copy2(OVERLAY / name, ROOT / 'Palladium/Views' / name)
(ROOT / 'Palladium/Views/Tabs/FormatPickerSheetView.swift').write_text('// Source-aware replacement is in GlintDesign.swift.\n')

# Replace only the home layout. Keep the original options, gallery, history and callbacks.
home = ROOT / 'Palladium/Views/Tabs/DownloadTabView.swift'
text = home.read_text()
start = text.index('    var body: some View {')
end = text.index('        .sheet(isPresented: $showHistorySheet)', start)
text = text[:start] + '''    var body: some View {
        GlintHome(url: $urlText, running: isRunning, resolving: isResolvingFormats || isResolvingGallery,
            connected: useCookies && !selectedCookieFileName.isEmpty, progress: progressText,
            error: downloadErrorText, queueCount: downloadQueue.outstandingCount, status: statusText,
            downloadTitle: selectedPreset == .autoVideo ? "Download best quality" : selectedPreset == .mute ? "Download video without audio" : "Download " + selectedPreset.title,
            onDownload: primaryDownloadAction, onInspect: onChooseFormat, onCancel: onCancel,
            onPaste: onPastedURL, onOptions: { showDownloadOptions = true },
            onHistory: { showHistorySheet = true }, onQueue: { showDownloadQueueSheet = true },
            onConnect: { NotificationCenter.default.post(name: Notification.Name("GlintConnectInstagram"), object: nil) })
        .sheet(isPresented: $showDownloadOptions) {
            NavigationStack {
                Form {
                    Section("Download mode") {
                        Picker("Mode", selection: $selectedPreset) {
                            ForEach(visibleDownloadPresets) { preset in Text(preset.title).tag(preset) }
                        }
                        Toggle("Download playlist", isOn: $downloadPlaylist)
                        Toggle("Include subtitles", isOn: $downloadSubtitles)
                        Toggle("Embed thumbnail", isOn: $embedThumbnail)
                        if downloadSubtitles { subtitleDownloadOptionRow }
                    }
                    Section("Session") { cookieSelectionRow }
                    Section {
                        Text("Video mode downloads the highest available resolution, preferring HDR at the same resolution. Incompatible videos automatically get a high-quality playable copy. Originals are retained. Use Library to save to Photos or Files.").font(.caption).foregroundStyle(.secondary)
                    }
                }.navigationTitle("Options").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDownloadOptions = false } } }
            }.presentationDetents([.medium, .large])
        }
''' + text[end:]
home.write_text(text)

content = 'Palladium/Views/ContentView.swift'
change(content, 'struct ContentView: View {', '''struct ContentView: View {
    @State private var glintShowInstagram = false
    @State private var glintBrowser: GlintBrowserTarget?
    @AppStorage("glint.showConsole") private var glintShowConsole = false''')
change(content, '                SettingsTabView(', '                GlintSettingsShell(onConnect: { glintShowInstagram = true }) { SettingsTabView(')
change(content, '                    onDeleteCookieFile: deleteImportedCookieFile\n                )', '                    onDeleteCookieFile: deleteImportedCookieFile\n                ) }')
change(content, '''                ConsoleTabView(logStore: consoleLogStore)
                    .tabItem {
                        Label(String(localized: "tab.console", bundle: .app), systemImage: "terminal")
                    }
                    .tag(AppTab.console)''', '''                if glintShowConsole {
                    ConsoleTabView(logStore: consoleLogStore)
                        .tabItem { Label("Console", systemImage: "terminal") }
                        .tag(AppTab.console)
                }''')
change(content, '        .onChange(of: selectedPreset, initial: false)', '''        .tint(GlintPalette.accent)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GlintConnectInstagram"))) { _ in glintShowInstagram = true }
        .sheet(isPresented: $glintShowInstagram) { GlintInstagramLogin(onImport: importBrowserCookies) }
        .onReceive(NotificationCenter.default.publisher(for: .glintOpenInstagram)) { notification in
            glintBrowser = GlintBrowserTarget(url: notification.object as? URL ?? GlintInstagramURL.home)
        }
        .sheet(item: $glintBrowser) { target in GlintInstagramBrowser(url: target.url) }
        .onReceive(NotificationCenter.default.publisher(for: .glintBrowserAction)) { notification in
            if let action = notification.object as? GlintBrowserAction { glintHandleBrowserAction(action) }
        }
        .onChange(of: isRunning || isPackageRunning || isResolvingFormats || isResolvingGallery, initial: true) { _, busy in
            GlintBrowserActivity.shared.busy = busy
        }
        .onChange(of: selectedPreset, initial: false)''')
change(content, 'onOpenOptions: openSavedDownloadActions\n                )', 'onOpenOptions: openSavedDownloadActions,\n                    isEngineBusy: isRunning || isPackageRunning\n                )')
change(content, 'Label(String(localized: "tab.downloads", bundle: .app), systemImage: "tray.and.arrow.down")', 'Label("Library", systemImage: "square.grid.2x2")')

# Source selection must not be prefiltered to H.264/SDR by the upstream defaults.
options = 'Palladium/Models/DownloadOptions.swift'
change(options, 'var videoCodec: VideoDownloadCodec = .photosCompatible', 'var videoCodec: VideoDownloadCodec = .best')
change(options, 'VideoDownloadCodec(rawValue: defaults.string(forKey: videoCodecKey) ?? "") ?? .photosCompatible', 'VideoDownloadCodec(rawValue: defaults.string(forKey: videoCodecKey) ?? "") ?? .best')
change(options, '    private func videoArguments(includeAudio: Bool) -> String {', '''    private func videoArguments(includeAudio: Bool) -> String {
        if videoCodec == .best && videoQuality == .best {
            return GlintSourceQuality.downloadArguments(includeAudio: includeAudio)
        }''')
change(options, '''            return "--merge-output-format mp4 --remux-video mp4 "
                + "-S vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"''', '''            return GlintSourceQuality.downloadArguments()''')

# The primary video action and automatic queue must keep the source-quality promise
# even if an older install saved conversion, codec, thumbnail or website overrides.
flow = 'Palladium/Views/ContentView+DownloadFlow.swift'
change(flow, '    func handlePastedURL(_ pastedURL: String) {\n        guard autoDownloadOnPaste else { return }', '''    func handlePastedURL(_ pastedURL: String) {
        urlText = ClipboardLinkDetector.firstLink(in: pastedURL) ?? pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autoDownloadOnPaste else { return }''')
change(flow, '        let queuedBatchQuality = queuedConfiguration?.batchQuality', '''        let queuedBatchQuality = queuedConfiguration?.batchQuality
        let glintSourceBest = formatOverride == nil && queuedBatchQuality == nil
            && (effectiveDownloadPreset == .autoVideo || effectiveDownloadPreset == .mute)''')
change(flow, '        if let formatOverride {\n            let formatPreset:', '        if glintSourceBest {\n            presetAtStart = DownloadPreset.custom.pythonValue\n        } else if let formatOverride {\n            let formatPreset:')
change(flow, '        if let formatOverride {\n            let formatArguments', '''        if glintSourceBest {
            extraArgsAtStart = GlintSourceQuality.downloadArguments(includeAudio: effectiveDownloadPreset != .mute)
                + " --sleep-requests 2 --retries 1 --extractor-retries 0"
        } else if let formatOverride {
            let formatArguments''')
change(flow, '        let postProcessingJSONAtStart = postProcessing.configurationJSON(for: postProcessingPreset)',
    '        let postProcessingJSONAtStart = (glintSourceBest ? PostProcessingPreferences() : postProcessing).configurationJSON(for: postProcessingPreset)')
change(flow, '''        let presetArgsJSONAtStart = usesQualitySettings
            ? queuedConfiguration?.presetArgumentsJSON ?? buildPresetArgumentsJSON()
            : "{}"''', '''        let presetArgsJSONAtStart = glintSourceBest ? "{}" : (usesQualitySettings
            ? queuedConfiguration?.presetArgumentsJSON ?? buildPresetArgumentsJSON()
            : "{}")''')
change(flow, '        let embedThumbnailAtStart = queuedConfiguration?.embedThumbnail ?? embedThumbnail',
    '        let embedThumbnailAtStart = glintSourceBest ? false : (queuedConfiguration?.embedThumbnail ?? embedThumbnail)')
change(flow, '            FFmpegBridgeControl.setLiveLogFD(nil)', '''            let glintPrepared: (paths: [String], primary: String?, note: String?)
            if (outcome.resultKind == "success" || outcome.resultKind == "partial" || outcome.statusText == "success"), !downloadCancelRequested {
                GlintOriginStore.ensure(paths: outcome.downloadedPaths, sourceURL: URL(string: targetURL))
                glintPrepared = await glintPrepareDownloads(paths: outcome.downloadedPaths, primary: outcome.primaryDownloadedPath)
            } else {
                glintPrepared = (outcome.downloadedPaths, outcome.primaryDownloadedPath, nil)
            }
            FFmpegBridgeControl.setLiveLogFD(nil)''')
change(flow, '                    items: outcome.downloadedPaths.map { URL(fileURLWithPath: $0) },\n                    primaryMediaURL: outcome.primaryDownloadedPath.map { URL(fileURLWithPath: $0) },',
    '                    items: glintPrepared.paths.map { URL(fileURLWithPath: $0) },\n                    primaryMediaURL: glintPrepared.primary.map { URL(fileURLWithPath: $0) },')
change(flow, '            if finalResultKind == "error" {', '''            if finalResultKind == "success" || finalResultKind == "partial" {
                progressText += "\\n" + (glintPrepared.note ?? "Ready to play. Open Library to save to Photos or Files.")
            }
            if finalResultKind == "error" {''')

# Add manifest metadata without inferring HDR from pixel depth or the filename.
runner = 'Palladium/Services/Python/PythonFlowRunner.swift'
change(runner, '    var hasThumbnail: Bool = false', '    var hasThumbnail: Bool = false\n    var dynamicRange: String? = nil\n    var thumbnailURL: String? = nil')
change(runner, '                hasThumbnail: item["has_thumbnail"] as? Bool ?? false', '''                hasThumbnail: item["has_thumbnail"] as? Bool ?? false,
                dynamicRange: item["dynamic_range"] as? String,
                thumbnailURL: item["thumbnail_url"] as? String''')
append(runner, '''extension PythonFlowRunner {
    static func glintMedia(function: String, path: String) async -> String {
        guard ["glint_inspect_media", "glint_make_photos_copy", "glint_transcode_photos_copy"].contains(function) else {
            return "{\\"success\\":false,\\"error\\":\\"Unknown operation\\"}"
        }
        return await runOnPythonThread {
            do {
                FFmpegBridgeControl.setLiveLogFD(nil)
                let module = try loadYtDlpModule()
                let callable = try pythonMember(module, named: function)
                let result = try callable.throwing.dynamicallyCall(withArguments: [path])
                return String(result) ?? "{}"
            } catch {
                let payload: [String: Any] = ["success": false, "error": error.localizedDescription]
                return String(data: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(), encoding: .utf8) ?? "{}"
            }
        }
    }
}''')
change('Palladium/Services/Python/palladium_ytdlp/ytdlp.py', '                "has_thumbnail": bool(info.get("thumbnails")),', '''                "has_thumbnail": bool(info.get("thumbnails")),
                "dynamic_range": source.get("dynamic_range"),
                "thumbnail_url": info.get("thumbnail"),''')
shutil.copy2(OVERLAY / 'glint_media.py', ROOT / 'Palladium/Services/Python/palladium_ytdlp/glint_media.py')
change('Palladium/Services/Python/PythonScripts.swift', '        "palladium_ytdlp/ytdlp.py",', '        "palladium_ytdlp/ytdlp.py",\n        "palladium_ytdlp/glint_media.py",')
append('Palladium/Services/Python/yt_dlp_flow.py', 'from palladium_ytdlp.glint_media import glint_inspect_media, glint_make_photos_copy, glint_transcode_photos_copy')

# Capture each completed item's own URL/creator, including playlist entries.
shutil.copy2(OVERLAY / 'glint_origin.py', ROOT / 'Palladium/Services/Python/palladium_ytdlp/glint_origin.py')
change('Palladium/Services/Python/PythonScripts.swift', '        "palladium_ytdlp/ytdlp.py",', '        "palladium_ytdlp/ytdlp.py",\n        "palladium_ytdlp/glint_origin.py",')
append('Palladium/Services/Python/palladium_ytdlp/ytdlp.py', 'from .glint_origin import capture_origins')
change('Palladium/Services/Python/palladium_ytdlp/ytdlp.py',
    '                                filter_embedded_playlist_entries(filter_embedded_entries),',
    '                                filter_embedded_playlist_entries(filter_embedded_entries),\n                                capture_origins(run_output_dir or downloads_dir or os.getcwd(), download_url),')

# Keep per-file provenance attached through atomic saves, collision renames and
# converted copies. It never becomes an extra media item in Photos or the player.
post = 'Palladium/Views/ContentView+PostDownload.swift'
change(post, '                try fileManager.copyItem(at: itemURL, to: itemDestination)',
    '                try fileManager.copyItem(at: itemURL, to: itemDestination)\n                try GlintOriginStore.copy(from: itemURL, to: itemDestination)')
change(post, '                try fileManager.copyItem(at: itemURL, to: stagedItem)',
    '                try fileManager.copyItem(at: itemURL, to: stagedItem)\n                try GlintOriginStore.copy(from: itemURL, to: stagedItem)')
change(post, '                appendedItems.append(destination)',
    '                appendedItems.append(destination)\n                try GlintOriginStore.copy(from: stagedItem, to: destination)')
change(post, '                try? fileManager.removeItem(at: appendedItem)',
    '                try? fileManager.removeItem(at: appendedItem)\n                try? fileManager.removeItem(at: GlintOriginStore.sidecar(appendedItem))')
change(post, '                }\n                cleanupTemporaryDownloadSource(for: result)',
    '                }\n                try GlintOriginStore.writeLinks(in: destinationFolder)\n                cleanupTemporaryDownloadSource(for: result)')
change(post, '                try FileManager.default.copyItem(at: itemURL, to: destination)',
    '                try FileManager.default.copyItem(at: itemURL, to: destination)\n                try GlintOriginStore.copy(from: itemURL, to: destination)\n                try GlintOriginStore.writeLink(for: destination)')

# Private sessions: no credentials in the Files-visible Documents directory or backups.
change('Palladium/Views/ContentView+Cookies.swift', '        try documentsDirectoryURL().appendingPathComponent("Cookies", isDirectory: true)', '        try GlintPrivateStorage.cookiesDirectory()')
change('Palladium/Views/ContentView+Cookies.swift', '        try text.write(to: destinationURL, atomically: true, encoding: .utf8)', '        try Data(text.utf8).write(to: destinationURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])')
app = 'Palladium/PalladiumApp.swift'
change(app, '        retainFFmpegBridgeExports()', '        GlintDefaults.configure()\n        retainFFmpegBridgeExports()')
change(app, '            let cookiesDir = documents.appendingPathComponent("Cookies", isDirectory: true)', '            let cookiesDir = try GlintPrivateStorage.cookiesDirectory()')
change(app, '                Cookies: imported Netscape cookie files for yt-dlp', '                Sessions are stored privately, outside this folder.')
change(app, '        setenv("PYTHONHOME", pythonRoot.path, 1)', '''        setenv("SSL_CERT_FILE", bundle.bundleURL.appendingPathComponent("python-packages/certifi/cacert.pem").path, 1)
        setenv("PYTHONHOME", pythonRoot.path, 1)''')
append('Palladium/Views/GlintDesign.swift', '''enum GlintDefaults {
    static func configure() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "glint.defaults.v1") else { return }
        defaults.set(false, forKey: "palladium.autoDownloadOnPaste")
        defaults.set(false, forKey: "palladium.autoPasteLinkEnabled")
        defaults.set(false, forKey: "palladium.checkPackageUpdatesOnLaunch")
        defaults.set(false, forKey: "palladium.autoUpdatePackagesOnLaunch")
        defaults.set(false, forKey: "palladium.autoRetryFailedDownloads")
        defaults.set(false, forKey: "palladium.askUserAfterDownload")
        defaults.set("saveToApplicationFolder", forKey: "palladium.afterDownloadBehavior")
        defaults.set("saveToApplicationFolder", forKey: "palladium.selectedPostDownloadAction")
        defaults.set("--sleep-requests 2 --retries 1 --extractor-retries 0", forKey: "palladium.extraArgs")
        defaults.set(true, forKey: "glint.defaults.v1")
    }
}''')
append('Palladium/Views/Tabs/Settings/CookieWebsiteImportView.swift', '''struct GlintInstagramLogin: View {
    let onImport: ([HTTPCookie], URL) throws -> Void
    @Environment(\\.dismiss) private var dismiss
    @State private var accepted = false
    private let source = URL(string: "https://www.instagram.com/accounts/login/")!
    var body: some View {
        NavigationStack {
            if accepted {
                CookieLoginBrowserView(sourceURL: source, onCancel: { dismiss() }, onImport: { cookies in
                    let scoped = cookies.filter {
                        let host = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                        return host == "instagram.com" || host.hasSuffix(".instagram.com")
                    }
                    guard scoped.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) else {
                        throw NSError(domain: "Glint", code: 1, userInfo: [NSLocalizedDescriptionKey: "Complete Instagram sign-in before importing the session."])
                    }
                    try onImport(scoped, source)
                    dismiss()
                })
            } else {
                ZStack {
                    GlintBackdrop()
                    VStack(alignment: .leading, spacing: 24) {
                        GlintMark(size: 64)
                        Text("Your account.\\nYour device.").font(.largeTitle.bold())
                        Text("Sign in on Instagram’s own website. Glint imports only Instagram cookies into protected local storage; no Glint server receives your login.")
                        Text("Automated downloads can trigger Instagram verification or account restrictions. HDR is not guaranteed. Glint stops on access rejections; do not repeatedly retry a challenged account.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Continue to Instagram") { accepted = true }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        Spacer()
                    }.padding(28)
                }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }.tint(GlintPalette.accent)
    }
}''')

# A bounded thumbnail library; the original file management and folder navigation remain.
library = ROOT / 'Palladium/Views/Tabs/SavedDownloadsTabView.swift'
text = library.read_text()
text = text.replace('    let onOpenOptions: (SavedDownloadItem) -> Void', '    let onOpenOptions: (SavedDownloadItem) -> Void\n    var isEngineBusy: Bool = false\n    @State private var glintInspection: GlintInspectionTarget?', 1)
start = text.index('    var body: some View {')
end = text.index('    private func loadItems()', start)
text = text[:start] + '''    var body: some View {
        NavigationStack {
            ZStack {
                GlintBackdrop()
                if let loadError {
                    ContentUnavailableView("Could not load library", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if items.isEmpty {
                    ContentUnavailableView("A little room for brilliance", systemImage: "square.stack.3d.up", description: Text("Your saved downloads appear here. Long-press a video for quality inspection and Photos export."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 14)], spacing: 18) {
                            ForEach(items) { item in
                                if item.isFolder {
                                    NavigationLink(value: item) { GlintLibraryTile(item: item) }.buttonStyle(.plain)
                                } else {
                                    VStack(spacing: 8) {
                                    Button { openMedia(item) } label: { GlintLibraryTile(item: item) }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Quality & Photos copy", systemImage: "sparkles.tv") { glintInspection = GlintInspectionTarget(url: item.url) }.disabled(isEngineBusy)
                                            Button("Share & save", systemImage: "square.and.arrow.up") { onOpenOptions(item) }
                                            Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                                        }
                                    if DownloadedMediaGroup.classify(item.url) == .video {
                                        Button("Save & source", systemImage: "square.and.arrow.down") { glintInspection = GlintInspectionTarget(url: item.url) }
                                            .buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(isEngineBusy)
                                    }
                                    }
                                }
                            }
                        }.padding(20)
                    }.refreshable { loadItems() }
                }
            }.navigationTitle("Library")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise", action: loadItems) } }
                .navigationDestination(for: SavedDownloadItem.self) { item in
                    SavedDownloadsFolderView(folder: item, onOpenOptions: onOpenOptions, onOpenPlayback: openMedia)
                }
        }.tint(GlintPalette.accent)
            .onAppear(perform: loadItems)
            .onChange(of: showsTemporaryDownloads) { loadItems() }
            .sheet(item: $playbackItem) { item in SavedMediaPlayerView(item: item) }
            .sheet(item: $glintInspection) { item in GlintMediaSheet(url: item.url) }
    }

''' + text[end:]
# Nested folders get the same quality action, not only top-level files.
text = text.replace('private struct SavedDownloadsFolderView: View {', 'private struct SavedDownloadsFolderView: View {\n    @State private var glintInspection: GlintInspectionTarget?')
text = text.replace('        .navigationTitle(folder.displayName)', '        .safeAreaInset(edge: .top) { GlintFolderSourceView(folder: folder.url) }\n        .navigationTitle(folder.displayName)')
needle = '                                    onOpenOptions(item)\n                                }'
# Preserve all existing actions; add inspection to media rows inside folders.
text = text.replace('                                    onOpenPlayback(item)\n                                }', '                                    onOpenPlayback(item)\n                                }\n                                .contextMenu { Button("Save to Photos or Files", systemImage: "square.and.arrow.down") { glintInspection = GlintInspectionTarget(url: item.url) } }')
text = text.replace('''                            SavedDownloadRow(item: item) {
                                onOpenOptions(item)
                            }''', '''                            SavedDownloadRow(item: item) {
                                if DownloadedMediaGroup.classify(item.url) == .video {
                                    glintInspection = GlintInspectionTarget(url: item.url)
                                } else { onOpenOptions(item) }
                            }''')
text = text.replace('''        .onAppear(perform: loadItems)
    }

    private func loadItems()''', '''        .onAppear(perform: loadItems)
        .sheet(item: $glintInspection) { target in GlintMediaSheet(url: target.url) }
    }

    private func loadItems()''')
library.write_text(text)

# Restore normal TLS validation instead of inheriting permissive extractor settings.
for path in (ROOT / 'Palladium/Services/Python').rglob('*.py'):
    text = path.read_text().replace('"nocheckcertificate": True', '"nocheckcertificate": False')
    # yt-dlp accepts the singular spelling too; upstream uses both spellings.
    text = re.sub(r'''["']--no-check-certificates?["'],?''', '', text)
    path.write_text(text)

# Generate a full-size app asset. iOS supplies the external icon mask.
from PIL import Image, ImageDraw
size = 1024
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        t = (x + y) / (2 * size)
        pixels[x, y] = (int(247 - 48*t), int(116 - 63*t), int(67 + 21*t))
draw = ImageDraw.Draw(image, 'RGBA')
draw.rounded_rectangle((163, 158, 873, 868), radius=200, fill=(255,255,255,33), outline=(255,255,255,130), width=4)
draw.line([(375,390),(650,665)], fill=(255,255,255,245), width=76)
draw.line([(440,665),(650,665),(650,455)], fill=(255,255,255,245), width=76, joint='curve')
draw.polygon([(337,234),(359,293),(419,315),(359,337),(337,397),(315,337),(255,315),(315,293)], fill=(255,255,255,235))
iconset = assets / 'GlintIcon.appiconset'
iconset.mkdir(exist_ok=True)
image.save(iconset / 'Glint.png')
entries = [{'idiom':'ios-marketing','size':'1024x1024','scale':'1x','filename':'Glint.png'}]
for idiom, points, scales in [('iphone',20,[2,3]),('iphone',29,[2,3]),('iphone',40,[2,3]),('iphone',60,[2,3]),('ipad',20,[1,2]),('ipad',29,[1,2]),('ipad',40,[1,2]),('ipad',76,[1,2]),('ipad',83.5,[2])]:
    for scale in scales:
        name = f'{idiom}-{points}-{scale}.png'
        image.resize((int(points*scale),int(points*scale)), Image.Resampling.LANCZOS).save(iconset/name)
        entries.append({'idiom':idiom,'size':f'{points}x{points}','scale':f'{scale}x','filename':name})
(iconset/'Contents.json').write_text(json.dumps({'images':entries,'info':{'author':'xcode','version':1}},indent=2))
print('Glint overlays applied successfully.')
