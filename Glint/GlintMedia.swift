// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Foundation
import AVFoundation
import Photos
import UIKit

struct GlintInspectionTarget: Identifiable {
    let url: URL
    var id: URL { url }
}

struct GlintMediaReport: Decodable {
    let success: Bool
    let error: String?
    var verifiedHDR: Bool? = nil
    var rangeLabel: String? = nil
    var bitDepth: Int? = nil
    var dolbyVision: Bool? = nil
    var transfer: String? = nil
    var primaries: String? = nil
    var codec: String? = nil
    var width: Int? = nil
    var height: Int? = nil
    var size: Int64? = nil
    var path: String? = nil
    var sourceUnchanged: Bool? = nil
    var note: String? = nil
    var videoCopied: Bool? = nil
    var retryWithEncode: Bool? = nil
}

struct GlintMediaSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var report: GlintMediaReport?
    @State private var copy: URL?
    @State private var busy = false
    @State private var message: String?
    @State private var canSaveOriginal = false
    var body: some View {
        NavigationStack {
            ZStack {
                GlintBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "sparkles.tv").font(.system(size: 50, weight: .light)).foregroundStyle(GlintPalette.accent).padding(.top, 20)
                        Text(url.lastPathComponent).font(.title3.bold()).textSelection(.enabled)
                        GlintOriginCard(url: url).disabled(busy)
                        if let report, report.success {
                            VStack(alignment: .leading, spacing: 16) {
                                GlintQualityBadge(text: report.rangeLabel ?? "Range unknown", highlighted: report.verifiedHDR == true)
                                info("Video", (report.codec ?? "Unknown").uppercased())
                                if let w = report.width, let h = report.height { info("Resolution", "\(w) × \(h)") }
                                if let bits = report.bitDepth { info("Bit depth", "\(bits)-bit") }
                                info("Transfer", report.transfer ?? "Unknown")
                                info("Color primaries", report.primaries ?? "Unknown")
                                if let size = report.size { info("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                            }.padding(22).glintGlass()
                            Text(report.verifiedHDR == true ? "HDR color and bit-depth metadata verified in the saved file. This is not a guarantee of Dolby Vision playback in every player." : "The saved file does not contain enough metadata to verify HDR. A 10-bit codec alone is not proof of HDR.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let report {
                            Label(report.error ?? "Unable to inspect this file.", systemImage: "exclamationmark.circle").font(.subheadline)
                        } else {
                            HStack { ProgressView(); Text("Inspecting the actual file…").font(.subheadline) }
                        }
                        ShareLink(item: copy ?? url) {
                            Label("Save to Files or share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(busy)
                            Button { Task { await saveToPhotos(copy ?? url) } } label: {
                                Label("Save to Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 12)
                            }.buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(busy)
                        if !canSaveOriginal && copy == nil {
                            Button { Task { await makeCopy() } } label: {
                                Label("Prepare playable copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity).padding(.vertical, 12)
                            }.buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(busy || report?.success != true)
                        }
                        if busy { HStack(spacing: 10) { ProgressView(); Text("Processing on your iPhone. Keep Glint open.").font(.caption) } }
                        if let message { Text(message).font(.subheadline).textSelection(.enabled).padding(18).glintGlass(20) }
                        Text("Playable files are saved as-is. When needed, Glint first tries a lossless video remux, then high-quality HEVC at the original resolution and timing. HLG/PQ HDR must survive verification. Re-encoding can lose detail and Dolby Vision dynamic metadata; the original stays available in Files → Glint → Originals.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24)
                }
            }.navigationTitle("Quality & export").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }.tint(GlintPalette.accent).interactiveDismissDisabled(busy)
            .onReceive(NotificationCenter.default.publisher(for: .glintBrowserDownloadStarted)) { _ in dismiss() }
            .task {
                let payload = await PythonFlowRunner.glintMedia(function: "glint_inspect_media", path: url.path)
                report = decode(payload)
                canSaveOriginal = UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path)
            }
    }
    private func info(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.subheadline)
    }
    private func decode(_ value: String) -> GlintMediaReport {
        (try? JSONDecoder().decode(GlintMediaReport.self, from: Data(value.utf8))) ?? GlintMediaReport(success: false, error: "The media engine returned an unreadable result.")
    }
    @MainActor private func makeCopy() async {
        guard !busy else { return }
        guard ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical else {
            message = "Your iPhone is warm. Let it cool before creating a copy. Exporting the original needs no conversion."
            return
        }
        busy = true
        defer { busy = false }
        let result = await GlintPlayback.prepare(url, preserveOriginal: false)
        if await GlintPlayback.isCompatible(result.url) { copy = result.url }
        message = result.note
    }
    @MainActor private func saveToPhotos(_ source: URL) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let prepared = await GlintPlayback.prepare(source, preserveOriginal: false)
        let source = prepared.url
        if source != url { copy = source }
        guard await GlintPlayback.isCompatible(source) else {
            message = prepared.note ?? "Original retained. Photos could not import this video."
            return
        }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            message = "Allow Glint to add videos in iPhone Settings, or export to Files."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: source)
            }
            message = "Saved to Photos. The file in Glint is unchanged."
        } catch { message = error.localizedDescription }
    }
}

struct GlintLibraryTile: View {
    let item: SavedDownloadItem
    @State private var thumbnail: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22).fill(GlintPalette.accent.opacity(0.09))
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                } else {
                    Image(systemName: item.isFolder ? "folder.fill" : "play.rectangle.fill")
                        .font(.system(size: 38, weight: .light)).foregroundStyle(GlintPalette.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(item.isFolder ? "COLLECTION" : item.url.pathExtension.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.regularMaterial, in: Capsule()).padding(12)
            }.frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 22))
            Text(item.displayName).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
        }.padding(10).glintGlass(30)
            .task(id: item.url) {
                guard !item.isFolder else { return }
                if ["jpg", "jpeg", "png", "heic", "webp"].contains(item.url.pathExtension.lowercased()) {
                    // ImageIO decodes a bounded thumbnail, rather than a full-resolution image.
                    thumbnail = glintImageThumbnail(item.url)
                    return
                }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 500)
                if let result = try? await generator.image(at: .zero), !Task.isCancelled { thumbnail = UIImage(cgImage: result.image) }
            }
    }
}

import ImageIO
private func glintImageThumbnail(_ url: URL) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 500, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

enum GlintPrivateStorage {
    static func cookiesDirectory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = root.appendingPathComponent("GlintSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder
    }
}
