import SwiftUI

enum RinseTheme {
    static let accent = Color(red: 0.05, green: 0.76, blue: 0.76)
}

struct RinseView: View {
    @ObservedObject var store: RinseStore
    @State private var picker: PickerKind?
    @State private var showSettings = false
    @State private var showPrivacy = false
    @State private var showExport = false
    @State private var report: CleanResult?
    @State private var confirmClear = false
    @Environment(\.colorScheme) private var colorScheme
    enum PickerKind: String, Identifiable { case photos, files, folder; var id: String { rawValue } }
    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        hero
                        importControls
                        if store.importing {
                            HStack(spacing: 12) { ProgressView(); Text("Importing your selection…").font(.subheadline) }
                        }
                        if store.items.isEmpty { emptyState }
                        else { queue }
                    }
                    .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
                    .frame(maxWidth: 740)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Rinse").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Privacy", systemImage: "lock.shield") { showPrivacy = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                        .disabled(store.busy || store.importing)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $picker) { kind in
                if kind == .photos {
                    PhotoImporter { providers in picker = nil; store.importProviders(providers) }.ignoresSafeArea()
                } else {
                    FileImporter(folder: kind == .folder) { urls in picker = nil; store.importFiles(urls) }.ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(options: $store.options) }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .sheet(isPresented: $showExport) { ExportSheet(urls: store.results.map(\.output)).presentationDetents([.medium, .large]) }
            .sheet(item: $report) { ReportView(result: $0) }
            .alert("Rinse", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
            .confirmationDialog("Remove this session's temporary copies?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear session", role: .destructive) { store.clear() }
            } message: { Text("Save or share your clean copies first. Your original files and copies already exported elsewhere are not changed.") }
        }
    }
    private var background: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [RinseTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.11), .clear], center: .topTrailing, startRadius: 10, endRadius: 490)
            RadialGradient(colors: [Color.blue.opacity(0.07), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
        }.ignoresSafeArea()
    }
    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Share the moment.\nNot the metadata.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).minimumScaleFactor(0.8)
                Text("Clean photos and videos, entirely on your iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Image("Brand").resizable().aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80).clipShape(.rect(cornerRadius: 23)).accessibilityHidden(true)
        }.padding(.vertical, 14)
    }
    private var importControls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                importButton("Photos", icon: "photo.on.rectangle.angled", kind: .photos)
                importButton("Files", icon: "doc", kind: .files)
                importButton("Folder", icon: "folder", kind: .folder)
            }
        }.disabled(store.busy || store.importing)
    }
    private func importButton(_ title: String, icon: String, kind: PickerKind) -> some View {
        Button { picker = kind } label: {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }.frame(maxWidth: .infinity).frame(height: 91)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .accessibilityLabel("Import \(title.lowercased())")
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Nothing leaves until you share it", systemImage: "wifi.slash")
                .font(.headline)
            benefit("Personal tags removed", detail: "Location, camera details, dates and other embedded fields.", icon: "mappin.slash")
            benefit("Every output checked", detail: "See the metadata report and compare SHA-256 fingerprints.", icon: "checkmark.seal")
            benefit("Originals stay yours", detail: "Rinse creates separate copies. It never edits your source files.", icon: "square.on.square")
            Text("JPEG · PNG · HEIC · MOV · MP4\nSDR videos up to 4K / 60 fps. Photos export as SDR. No RAW, animated, HDR or spatial video support in version 1.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 10)
    }
    private func benefit(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(RinseTheme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var queue: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(store.items.count) selected").font(.title3.weight(.semibold))
                Spacer()
                Button("Clear", role: .destructive) { confirmClear = true }.disabled(store.busy || store.importing)
            }
            LazyVStack(spacing: 12) {
                ForEach(store.items) { item in
                    Button {
                        if let result = item.result { report = result }
                        else if let error = item.error { store.message = error }
                    } label: { row(item) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if item.state == .blocked || item.state == .cancelled { Button("Retry") { store.retry(item.id) } }
                        }
                }
            }
        }
    }
    private func row(_ item: QueueItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.kind == .photo ? "photo" : "film")
                .font(.title2).frame(width: 40).foregroundStyle(RinseTheme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                switch item.state {
                case .waiting: Text("Ready to clean").font(.caption).foregroundStyle(.secondary)
                case .cleaning:
                    ProgressView(value: item.fraction)
                    Text(item.fraction > 0.9 ? "Verifying export…" : "Cleaning…").font(.caption).foregroundStyle(.secondary)
                case .clean: Text("Verified · \(item.result?.before.fields.count ?? 0) fields removed").font(.caption).foregroundStyle(.secondary)
                case .blocked: Text("Not exported · tap for details").font(.caption).foregroundStyle(.orange)
                case .cancelled: Text("Cancelled · hold to retry").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: item.state == .clean ? "checkmark.circle.fill" : (item.state == .blocked ? "exclamationmark.triangle" : "circle.dotted"))
                .foregroundStyle(item.state == .blocked ? Color.orange : RinseTheme.accent)
        }
        .padding(16).glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if store.busy {
                Button("Stop cleaning", systemImage: "stop.fill") { store.cancel() }
                    .buttonStyle(.glass).controlSize(.large)
            } else if store.waiting > 0 {
                Button { store.clean() } label: {
                    Label("Clean \(store.waiting) \(store.waiting == 1 ? "copy" : "copies")", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.glassProminent).controlSize(.large).disabled(store.importing)
            }
            if !store.results.isEmpty && !store.busy {
                HStack(spacing: 12) {
                    Button("Save to Photos", systemImage: "square.and.arrow.down") { store.saveToPhotos() }
                        .buttonStyle(.glass).controlSize(.large)
                    Button("Share", systemImage: "square.and.arrow.up") { showExport = true }
                        .buttonStyle(.glassProminent).controlSize(.large)
                }
            }
        }.padding(.horizontal, 22).padding(.bottom, 12)
    }
}

struct SettingsView: View {
    @Binding var options: CleanOptions
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    Picker("Output format", selection: $options.photoFormat) {
                        ForEach(CleanOptions.PhotoFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text("Full dimensions, 8-bit sRGB. JPEG and HEIC are re-encoded at high quality. PNG preserves the rendered SDR pixels losslessly. HDR, depth and Live Photo motion are not retained.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Fresh file fingerprint", isOn: $options.freshFingerprint)
                } footer: {
                    Text("Adds new random, non-personal container padding and verifies that SHA-256 changed. This does not stop visual matching or make the media anonymous.")
                }
                Section("Video") {
                    Text("High-quality H.264 / AAC MP4, up to 4K and 60 fps. SDR only. Original resolution, frame timing and orientation are retained. Metadata tracks, chapters and subtitles are removed.")
                }
                Section("Storage") {
                    Text("Your originals are never overwritten. Temporary copies stay in excluded-from-backup cache storage until you clear this session or next open Rinse. Export copies you want to keep before closing the app.")
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("On your device") {
                    Text("Rinse contains no accounts, advertisements, analytics, model downloads or app networking code. Media cleaning runs locally.")
                    Text("The system Photos and Files pickers may download items from iCloud or another provider. For strictly offline use, choose files already stored on your iPhone. Exporting to a cloud folder or sharing service is your choice.")
                }
                Section("What verification means") {
                    Text("Rinse reconstructs supported media and checks the output for metadata exposed by ImageIO and AVFoundation. Technical information required to display or play the file remains. Optional random padding contains no source identity.")
                    Text("Metadata removal is not anonymity. Faces, addresses, watermarks, spoken details and information hidden inside pixels or sound are not removed. Other apps may attach new metadata after export.")
                }
                Section("Version 1 limits") {
                    Text("Single-frame JPEG, PNG and HEIC photos up to 64 MP; ordinary SDR MOV and MP4 videos up to 4K / 60 fps with mono or stereo audio. No RAW, animated photos, HDR or spatial video. Photo output is SDR, without depth or Live Photo motion.")
                    Text("The Share extension handles up to 10 photos, each up to 16 MP. Use the main app for larger photos and videos. Some sideloading containers do not load app extensions.")
                }
                Section("Before sharing") {
                    Text("Review the clean copy. Keep Rinse in the foreground while processing. The app reports verification failures and will not offer an unfinished or failed file for export.")
                }
            }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ReportView: View {
    let result: CleanResult
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Output verified", systemImage: "checkmark.seal.fill").foregroundStyle(RinseTheme.accent)
                    LabeledContent("Metadata fields found", value: "\(result.before.fields.count)")
                    LabeledContent("Remaining checked fields", value: "\(result.after.fields.count)")
                    LabeledContent("Output", value: result.after.mediaDescription)
                    LabeledContent("SHA-256 changed", value: result.hashChanged ? "Yes" : "No")
                }
                Section("Removed fields") {
                    if result.before.fields.isEmpty { Text("No checked personal metadata fields were detected in the imported file.").foregroundStyle(.secondary) }
                    ForEach(result.before.fields, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
                Section("SHA-256") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original").font(.caption).foregroundStyle(.secondary)
                        Text(result.originalHash).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("Clean copy").font(.caption).foregroundStyle(.secondary)
                        Text(result.cleanedHash).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                Section("Important") { ForEach(result.notes, id: \.self) { Text($0).font(.footnote) } }
            }.navigationTitle("Cleaning report").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
