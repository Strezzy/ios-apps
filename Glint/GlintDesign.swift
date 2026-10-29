// SPDX-License-Identifier: GPL-3.0-or-later
// Glint interface. The downloader engine is derived from Palladium; see README.md.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GlintGlass: ViewModifier {
    var radius: CGFloat = 26
    @Environment(\.accessibilityReduceTransparency) private var opaque
    func body(content: Content) -> some View {
        if opaque {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.3)))
        }
    }
}

extension View {
    func glintGlass(_ radius: CGFloat = 26) -> some View { modifier(GlintGlass(radius: radius)) }
}

enum GlintPalette {
    static let accent = Color(red: 0.94, green: 0.36, blue: 0.16)
}

struct GlintBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                Ellipse().fill(GlintPalette.accent.opacity(scheme == .dark ? 0.18 : 0.16))
                    .frame(width: proxy.size.width * 1.25, height: 340).blur(radius: 80)
                    .offset(x: -120, y: -proxy.size.height * 0.30)
                Ellipse().fill(Color.pink.opacity(scheme == .dark ? 0.12 : 0.09))
                    .frame(width: 320, height: 420).blur(radius: 90)
                    .offset(x: 160, y: proxy.size.height * 0.20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlintMark: View {
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(LinearGradient(colors: [GlintPalette.accent, .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "arrow.down.right").font(.system(size: size * 0.48, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Image(systemName: "sparkle").font(.system(size: size * 0.20, weight: .medium)).foregroundStyle(.white.opacity(0.9)).offset(x: -size * 0.22, y: -size * 0.20)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct GlintHome: View {
    @Binding var url: String
    let running: Bool
    let resolving: Bool
    let connected: Bool
    let progress: String
    let error: String?
    let queueCount: Int
    let status: String
    let downloadTitle: String
    let onDownload: () -> Void
    let onInspect: () -> Void
    let onCancel: () -> Void
    let onPaste: (String) -> Void
    let onOptions: () -> Void
    let onHistory: () -> Void
    let onQueue: () -> Void
    let onConnect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var pasteMessage: String?
    private var busy: Bool { running || resolving }
    private var hasURL: Bool { !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var progressFraction: Double? {
        let lines = progress.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard let range = line.range(of: #"[0-9]+(?:\.[0-9]+)?%"#, options: .regularExpression),
                  let value = Double(line[range].dropLast()) else { continue }
            return min(1, max(0, value / 100))
        }
        return nil
    }
    var body: some View {
        ZStack {
            GlintBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        GlintMark()
                        Text("Glint").font(.system(.title2, design: .rounded, weight: .bold))
                        Spacer()
                        Button(action: onHistory) { Image(systemName: "clock").frame(width: 46, height: 46) }
                            .glintGlass(23).accessibilityLabel("Link history")
                        Button(action: onQueue) {
                            Image(systemName: "tray.and.arrow.down").frame(width: 46, height: 46)
                                .overlay(alignment: .topTrailing) {
                                    if queueCount > 0 { Text("\(queueCount)").font(.caption2.bold()).padding(5).background(GlintPalette.accent, in: Circle()).foregroundStyle(.white) }
                                }
                        }.glintGlass(23).accessibilityLabel("Download queue, \(queueCount) remaining")
                    }.foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keep a little\nbrilliance.")
                            .font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.4)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        Text("Your favorite moments. The best available streams.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label("A LINK IS ALL IT TAKES", systemImage: "link")
                                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(.secondary)
                            Spacer()
                            Button(action: onOptions) { Image(systemName: "slider.horizontal.3").frame(width: 36, height: 36) }
                                .accessibilityLabel("Download options").disabled(busy)
                        }
                        TextField("Paste a Reel or video link", text: $url, axis: .vertical)
                            .font(.body).lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().focused($focused).disabled(busy)
                            .accessibilityLabel("Video link").submitLabel(.done)
                        HStack {
                            PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                                Task { @MainActor in
                                    guard let text = await GlintPaste.read(providers) else {
                                        pasteMessage = "Copy a video link, then tap Paste. You can also touch and hold the link field to paste."
                                        return
                                    }
                                    url = text
                                    pasteMessage = nil
                                    onPaste(text)
                                    focused = false
                                }
                            }.buttonBorderShape(.capsule).labelStyle(.titleAndIcon).disabled(busy)
                            Spacer()
                            if hasURL {
                                Button("Clear", systemImage: "xmark") { url = "" }
                                    .font(.caption).foregroundStyle(.secondary).disabled(busy)
                            }
                        }
                        if let pasteMessage { Text(pasteMessage).font(.caption).foregroundStyle(.secondary) }
                        Divider().opacity(0.45)
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles.tv").font(.title3).foregroundStyle(GlintPalette.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Highest quality. Ready for iPhone.").font(.subheadline.weight(.semibold))
                                Text("Maximum available resolution, with HDR when available. We prepare a playable copy only when needed.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("Instagram sign-in may unlock HDR and additional streams. Without HDR, you still get the best available video.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(22).glintGlass(30)
                    if busy {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                ProgressView().tint(GlintPalette.accent)
                                Text(resolving && !running ? "Finding available streams…" : progress.hasPrefix("Preparing") ? "Preparing for iPhone…" : "Saving your moment…").font(.headline)
                                Spacer()
                            }
                            if let fraction = progressFraction, running { ProgressView(value: fraction).tint(GlintPalette.accent) }
                            if !progress.isEmpty && running {
                                Text(String(progress.suffix(350))).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(4)
                            }
                            if running { Button("Cancel download", role: .destructive, action: onCancel).font(.subheadline) }
                        }.padding(22).glintGlass()
                    } else {
                        VStack(spacing: 12) {
                            Button { focused = false; onDownload() } label: {
                                Label(downloadTitle, systemImage: "arrow.down")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(GlintPalette.accent).disabled(!hasURL)
                            Button(action: onInspect) {
                                Label("Inspect quality & choose", systemImage: "slider.horizontal.3")
                                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            }.glintGlass(24).buttonStyle(.plain).disabled(!hasURL)
                        }
                    }
                    if let error, !error.isEmpty {
                        DisclosureGroup {
                            Text(error).font(.caption).textSelection(.enabled).padding(.top, 8)
                        } label: {
                            Label("This download needs attention", systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
                        }.tint(.red).padding(18).glintGlass(22)
                    }
                    if !busy && ["success", "partial"].contains(status) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Download ready", systemImage: "checkmark.circle.fill").font(.headline)
                            Text(progress).font(.caption).foregroundStyle(.secondary)
                            Text("Open Library → Save for Photos or Files.").font(.subheadline)
                        }.padding(20).glintGlass()
                    }
                    Button {
                        NotificationCenter.default.post(name: .glintOpenInstagram, object: GlintInstagramURL.home)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "safari").font(.title2).foregroundStyle(GlintPalette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Browse Instagram").font(.headline)
                                Text("Your feed, Reels, and favorite creators. Find your next download.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").font(.subheadline)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).glintGlass()
                    }.buttonStyle(.plain)
                    Button(action: onConnect) {
                        HStack(spacing: 12) {
                            Image(systemName: connected ? "checkmark.shield" : "person.crop.circle.badge.checkmark").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connected ? "Instagram session selected" : "Connect Instagram · Optional").font(.subheadline.weight(.semibold))
                                Text(connected ? "Availability depends on the Reel and your session." : "Sign-in may unlock HDR. Public videos can still download without it.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.foregroundStyle(.primary)
                    }.buttonStyle(.plain).disabled(busy)
                    Text("Direct downloads · No intermediary server\nOnly download content you own or have permission to save.")
                        .font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 32).frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.tint(GlintPalette.accent)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: busy)
    }
}

struct GlintSettingsShell<Advanced: View>: View {
    let onConnect: () -> Void
    @ViewBuilder let advanced: () -> Advanced
    @AppStorage("glint.showConsole") private var showConsole = false
    @State private var showAdvanced = false
    var body: some View {
        NavigationStack {
            ZStack {
                GlintBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            GlintMark(size: 62)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Made to keep.").font(.title2.bold())
                                Text("Glint · Source-first video saving").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 16)
                        VStack(spacing: 0) {
                            settingRow("Instagram", detail: "Connect or refresh your session", icon: "person.crop.circle", action: onConnect)
                            Divider().padding(.leading, 52)
                            settingRow("Download preferences", detail: "Accounts, storage, formats & background tasks", icon: "slider.horizontal.3") { showAdvanced = true }
                        }.padding(8).glintGlass()
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Quality, without the guessing", systemImage: "sparkles.tv").font(.headline)
                            Text("Source means the best stream Instagram makes available, not the creator’s camera original. HDR labels come from stream metadata. Check a saved file in Library to verify its actual color information.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Playable downloads save to Library automatically. Incompatible videos get a high-quality HEVC copy at the original resolution and frame timing. HLG/PQ HDR is verified after conversion. Originals remain in Files → Glint → Originals. Dolby Vision dynamic metadata is not recreated during conversion.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(22).glintGlass()
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Show diagnostic console", isOn: $showConsole)
                            Text("Logs stay in the app. Avoid sharing logs containing private links or account details.").font(.caption).foregroundStyle(.secondary)
                        }.padding(22).glintGlass()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Open source. On device.").font(.headline)
                            Text("Built on Palladium, yt-dlp, Python, FFmpeg and the Instagram HDR plugin. GPL-3.0-or-later; dependency licenses are retained in the source release.")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("Source & acknowledgments", destination: URL(string: "https://github.com/Strezzy/ios-apps/tree/main/Glint")!)
                        }.padding(.horizontal, 4)
                    }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Settings")
        }.tint(GlintPalette.accent)
            .sheet(isPresented: $showAdvanced) {
                advanced().safeAreaInset(edge: .top) {
                    HStack { Text("Preferences").font(.headline); Spacer(); Button("Done") { showAdvanced = false } }
                        .padding().background(.bar)
                }
            }
    }
    private func settingRow(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 30).foregroundStyle(GlintPalette.accent)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).foregroundStyle(.primary)
        }.buttonStyle(.plain)
    }
}

struct GlintQualityBadge: View {
    let text: String
    let highlighted: Bool
    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.4)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(highlighted ? GlintPalette.accent.opacity(0.14) : Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(highlighted ? GlintPalette.accent : .secondary)
    }
}

extension YTDLPFormat {
    var glintIsHDR: Bool {
        ["HLG", "HDR10", "HDR10+", "HDR", "DV", "DOLBY VISION", "PQ"].contains((dynamicRange ?? "").uppercased())
    }
    var glintRangeLabel: String {
        guard let range = dynamicRange, !range.isEmpty else { return "Range unknown" }
        return range.uppercased() == "SDR" ? "SDR" : range
    }
}

struct FormatPickerSheetView: View {
    let title: String
    let formats: [YTDLPFormat]
    let embedThumbnail: Bool
    let onSelect: (YTDLPFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = 0
    private var displayed: [YTDLPFormat] {
        formats.reversed().filter { filter == 0 || (filter == 1 ? $0.glintIsHDR : $0.isPhotosCompatible) }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                GlintBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let thumbnail = formats.compactMap(\.thumbnailURL).first, let url = URL(string: thumbnail) {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                                .frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        Text(title).font(.title3.bold()).lineLimit(3)
                        Text("These are the streams the service returned. HDR here is reported metadata; the saved-file inspector performs a separate check.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Filter formats", selection: $filter) { Text("All").tag(0); Text("HDR").tag(1); Text("Photos").tag(2) }.pickerStyle(.segmented)
                        if displayed.isEmpty {
                            ContentUnavailableView("No matching streams", systemImage: "sparkles.tv", description: Text("This response contains no matching format. Connecting Instagram may expose HDR, but cannot create it."))
                        }
                        ForEach(displayed) { format in
                            Button { onSelect(format) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(format.qualityHeading).font(.title3.bold())
                                            Text(format.videoCodecDisplayName.isEmpty ? format.audioCodec : format.videoCodecDisplayName)
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        GlintQualityBadge(text: format.glintRangeLabel, highlighted: format.glintIsHDR)
                                    }
                                    HStack(spacing: 10) {
                                        if let w = format.width, let h = format.height { Text("\(w) × \(h)") }
                                        if let fps = format.framesPerSecond { Text("\(Int(fps.rounded())) fps") }
                                        Text(format.finalVideoExtension(embedThumbnail: embedThumbnail).uppercased())
                                    }.font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        if let bitrate = format.videoBitrate, bitrate > 0 { Text(String(format: "%.1f Mb/s", bitrate / 1000)).font(.caption.monospacedDigit()) }
                                        if let size = format.fileSize { Text((format.fileSizeIsApproximate ? "≈ " : "") + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption) }
                                        Spacer()
                                        Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(GlintPalette.accent)
                                    }
                                }.foregroundStyle(.primary).padding(20).glintGlass(24)
                            }.buttonStyle(.plain).accessibilityLabel("Download \(format.qualityHeading), \(format.glintRangeLabel), \(format.videoCodecDisplayName)")
                        }
                    }.padding(20)
                }
            }.navigationTitle("Choose quality").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.tint(GlintPalette.accent)
    }
}
