// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AVFoundation
import UIKit

@MainActor
enum GlintPlayback {
    struct Prepared {
        let url: URL
        let note: String?
    }

    static func isCompatible(_ url: URL) async -> Bool {
        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) else { return false }
        return (try? await AVURLAsset(url: url).load(.isPlayable)) == true
    }

    static func prepare(_ url: URL, preserveOriginal: Bool) async -> Prepared {
        if await isCompatible(url) { return Prepared(url: url, note: nil) }
        var source = url
        do {
            // Temporary downloads may be cleaned up by the next download. Keep
            // an independent original before beginning any automatic conversion.
            if preserveOriginal {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let folder = documents.appendingPathComponent("Originals", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                source = folder.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: source)
            }
            guard !Task.isCancelled else { throw CancellationError() }
            guard ProcessInfo.processInfo.thermalState != .critical else {
                return Prepared(url: url, note: "Download retained. iPhone is too hot to convert now; retry from Library when it cools.")
            }
            for function in ["glint_make_photos_copy", "glint_transcode_photos_copy"] {
                let json = await PythonFlowRunner.glintMedia(function: function, path: source.path)
                let report = try JSONDecoder().decode(GlintMediaReport.self, from: Data(json.utf8))
                guard report.success, let path = report.path else {
                    if function == "glint_make_photos_copy", report.retryWithEncode == true, !Task.isCancelled { continue }
                    return Prepared(url: url, note: report.error ?? "Download retained; playable copy could not be prepared.")
                }
                let generated = URL(fileURLWithPath: path)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: generated)
                    throw CancellationError()
                }
                if await isCompatible(generated) {
                    let name = String(url.deletingPathExtension().lastPathComponent.prefix(80))
                    let destination = url.deletingLastPathComponent().appendingPathComponent("\(name) — iPhone \(UUID().uuidString.prefix(6)).mp4")
                    try FileManager.default.moveItem(at: generated, to: destination)
                    return Prepared(url: destination, note: report.note)
                }
                try? FileManager.default.removeItem(at: generated)
                // A remux may still have an unsupported profile/audio track.
                // Retry once with HEVC/AAC, but never lower resolution or HDR.
                if report.videoCopied != true { break }
            }
            return Prepared(url: url, note: "Download retained. iOS could not validate a playable copy at this source quality. The original is available in Files.")
        } catch {
            return Prepared(url: url, note: "Original retained. " + (Task.isCancelled ? "Conversion cancelled." : error.localizedDescription))
        }
    }
}

extension ContentView {
    @MainActor
    func glintPrepareDownloads(paths: [String], primary: String?) async -> (paths: [String], primary: String?, note: String?) {
        var ready: [String] = []
        var readyPrimary = primary
        var messages: [String] = []
        for path in paths {
            let source = URL(fileURLWithPath: path)
            guard !Task.isCancelled else { ready.append(path); continue }
            if DownloadedMediaGroup.classify(source) == .video {
                progressText = "Preparing for iPhone… Keeping source resolution and HDR."
                let result = await GlintPlayback.prepare(source, preserveOriginal: true)
                ready.append(result.url.path)
                if path == primary { readyPrimary = result.url.path }
                if let note = result.note { messages.append(note) }
            } else { ready.append(path) }
        }
        return (ready, readyPrimary, messages.isEmpty ? nil : Array(Set(messages)).sorted().joined(separator: "\n"))
    }
}
