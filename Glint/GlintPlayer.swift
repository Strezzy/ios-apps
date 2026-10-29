// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Combine
import AVKit
import CryptoKit

@MainActor private final class GlintPlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var working = false
    @Published var message: String?
    @Published var needsRetry = false
    private var statusObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var closed = false
    private var usedPreview = false
    private let source: URL
    init(source: URL) { self.source = source }

    func start() {
        closed = false
        task = Task {
            if (try? await AVURLAsset(url: source).load(.isPlayable)) == true {
                install(source)
            } else { await prepare() }
        }
    }
    func retry() { task = Task { await prepare() } }
    private func install(_ url: URL) {
        guard !closed, !Task.isCancelled else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed { Task { @MainActor in self?.playbackFailed() } }
        }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playbackFailed() }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
    }
    private func playbackFailed() {
        guard !working, !closed else { return }
        player?.pause(); player = nil
        if usedPreview { message = "iOS could not play this preview. Save to Files keeps the original."; return }
        retry()
    }
    private func cacheURL() throws -> URL {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = "\(source.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|preview-v1"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("GlintPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Previews are disposable: prune old entries and bound the cache to 1 GB.
        let entries = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []).sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        var bytes = 0
        for entry in entries {
            let info = try? entry.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            bytes += info?.fileSize ?? 0
            if bytes > 1_000_000_000 || (info?.contentModificationDate ?? .distantPast) < Date().addingTimeInterval(-7 * 86400) { try? FileManager.default.removeItem(at: entry) }
        }
        return folder.appendingPathComponent(key + ".mp4")
    }
    private func prepare() async {
        guard !working, !closed else { return }
        let activity = GlintBrowserActivity.shared
        guard !activity.busy, !activity.mediaBusy else {
            message = "A playable preview can be prepared when the current operation finishes. Save to Files is available now."
            needsRetry = true; return
        }
        working = true; needsRetry = false; activity.mediaBusy = true
        defer { working = false; activity.mediaBusy = false }
        message = "Preparing playback for this codec… Original quality stays untouched."
        do {
            let cache = try cacheURL()
            if FileManager.default.fileExists(atPath: cache.path), await GlintPlayback.isCompatible(cache) {
                usedPreview = true
                message = "Playback preview · up to 1080 pixels / 30 fps, SDR. Save to Files exports the original."
                install(cache); return
            }
            let payload = await PythonFlowRunner.glintMedia(function: "glint_make_preview", path: source.path)
            let report = try JSONDecoder().decode(GlintMediaReport.self, from: Data(payload.utf8))
            guard report.success, let path = report.path else {
                message = report.error ?? "Preview unavailable. Save the original to Files."; needsRetry = true; return
            }
            let generated = URL(fileURLWithPath: path)
            defer { try? FileManager.default.removeItem(at: generated) }
            guard !closed, !Task.isCancelled else { return }
            guard await GlintPlayback.isCompatible(generated) else {
                message = "iOS could not validate this preview. Save the original to Files."; return
            }
            try? FileManager.default.removeItem(at: cache)
            try FileManager.default.moveItem(at: generated, to: cache)
            usedPreview = true; message = report.note
            install(cache)
        } catch { message = "Preview unavailable: \(error.localizedDescription). Save to Files keeps the original."; needsRetry = true }
    }
    func close() {
        closed = true; task?.cancel(); player?.pause(); player = nil
        statusObservation = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct GlintPlayer: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GlintPlayerModel
    @ObservedObject private var activity = GlintBrowserActivity.shared
    @State private var exporting = false
    @State private var saving = false
    init(url: URL, title: String) {
        self.url = url; self.title = title
        _model = StateObject(wrappedValue: GlintPlayerModel(source: url))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let player = model.player { VideoPlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    Spacer()
                    Image(systemName: "play.rectangle").font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                    if model.working { ProgressView().padding() }
                    Spacer()
                }
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary).padding(16) }
                if model.needsRetry {
                    Button("Prepare playable preview") { model.retry() }.disabled(activity.busy || activity.mediaBusy).padding(.bottom, 12)
                }
                HStack(spacing: 12) {
                    Button("Save to Photos", systemImage: "photo.on.rectangle") { saving = true }.disabled(model.working)
                    Button("Save to Files", systemImage: "folder") { exporting = true }
                }.buttonStyle(.bordered).buttonBorderShape(.capsule).padding(.bottom, 16)
            }.background(Color.black.opacity(0.04))
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $exporting) { GlintFilesExporter(urls: [url]) { _ in exporting = false } }
            .sheet(isPresented: $saving) { GlintMediaSheet(url: url) }
            .onReceive(NotificationCenter.default.publisher(for: .glintOpenInstagram)) { _ in dismiss() }
            .onAppear { model.start() }.onDisappear { model.close() }
    }
}
