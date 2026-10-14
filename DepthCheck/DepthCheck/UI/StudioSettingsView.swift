import SwiftUI

struct StudioSettingsView: View {
    @EnvironmentObject private var store: StudioStore
    @State private var showFormats = false
    @State private var showPrivacy = false
    @State private var showCredits = false
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    modelCard
                    depthCard
                    processingCard
                    outputCard
                    privacyCard
                    Button("Restore default settings") { confirmReset = true }
                        .font(.footnote)
                        .buttonStyle(.glass)
                        .disabled(store.isBusy)
                        .frame(maxWidth: .infinity)
                    Text("Facet · \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFormats) { OutputFormatPicker(selection: $store.options.format) }
        .sheet(isPresented: $showPrivacy) { PrivacyInfoView() }
        .sheet(isPresented: $showCredits) { ModelCreditsView() }
        .confirmationDialog("Restore the default depth and export settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restore defaults") { store.resetOptions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your original media and existing exports are kept.")
        }
    }

    private var modelCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Depth model", symbol: "cpu")
                modelOption(.detailed, title: "Detailed", modelName: "Depth Anything 3 · Base", detail: "Larger model. Uses more memory and processing time.")
                Divider()
                modelOption(.balanced, title: "Balanced", modelName: "Depth Anything V2 · Small", detail: "Smaller model. Uses less memory.")
                InfoNote(text: "Models estimate depth at their working resolution. Exports retain the source dimensions.")
            }
            .disabled(store.isBusy)
        }
    }

    private func modelOption(_ model: DepthModelChoice, title: String, modelName: String, detail: String) -> some View {
        Button { store.options.model = model } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: store.options.model == model ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(store.options.model == model ? DepthCheckTheme.accent : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(modelName).font(.subheadline.weight(.medium)).foregroundStyle(DepthCheckTheme.accent.opacity(0.9))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(modelName). \(detail)")
        .accessibilityValue(store.options.model == model ? "Selected" : "")
    }

    private var depthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(text: "3D view", symbol: "view.3d")
                SettingRow("Screen plane", subtitle: "Sets which depth appears level with the screen.") {
                    HStack {
                        Text("Far")
                        Spacer()
                        Text(store.options.convergence.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(DepthCheckTheme.accent)
                        Spacer()
                        Text("Near")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Slider(value: $store.options.convergence, in: 0...1)
                        .accessibilityLabel("Screen plane")
                        .accessibilityValue(store.options.convergence.formatted(.percent.precision(.fractionLength(0))))
                }
                Divider()
                Toggle(isOn: $store.options.swapEyes) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Swap left & right").font(.headline)
                        Text("For viewers that expect reversed eye order.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DepthCheckTheme.accent)
            }
            .disabled(store.isBusy)
        }
    }

    private var processingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(text: "Video processing", symbol: "film.stack")
                Toggle(isOn: $store.options.memorySaver) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Memory saver").font(.headline)
                        Text("Reduces cached memory for large videos. May take longer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(isOn: $store.options.temporalStability) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Steadier video depth").font(.headline)
                        Text("Reduces flicker in unchanged areas. Strong depth can still show wobble.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(isOn: $store.options.preserveAudio) {
                    Text("Keep original audio").font(.headline)
                }
            }
            .tint(DepthCheckTheme.accent)
            .disabled(store.isBusy)
        }
    }

    private var outputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 19) {
                Eyebrow(text: "Export", symbol: "square.and.arrow.up")
                Button { showFormats = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("3D format").font(.headline).foregroundStyle(.primary)
                            Text(store.options.format.title).font(.subheadline).foregroundStyle(DepthCheckTheme.accent)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                SettingRow("Photo file type", subtitle: store.options.format == .spatial ? "Apple Spatial photos use stereo HEIC." : "PNG is lossless. HEIC and JPEG use compression.") {
                    Picker("Photo file type", selection: $store.options.photoEncoding) {
                        ForEach(PhotoEncoding.allCases) { format in Text(format.title).tag(format) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.options.format == .spatial)
                }
                InfoNote(text: "Video: HEVC (.mov). HDR exports as SDR.")
            }
            .disabled(store.isBusy)
        }
    }

    private var privacyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Button { showPrivacy = true } label: {
                    HStack {
                        Label("Privacy", systemImage: "lock.shield")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .font(.headline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                Button { showCredits = true } label: {
                    Label("Model credits & licenses", systemImage: "text.document")
                        .font(.footnote.weight(.medium))
                        .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct PrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StudioBackground()
                ScrollView {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 20) {
                            detail("On-device processing", symbol: "iphone",
                                   text: "Both depth models run on your iPhone. Depth Check does not upload your photos or videos.")
                            Divider()
                            detail("You choose what to share", symbol: "square.and.arrow.up",
                                   text: "Only selected media is imported. Saving to Photos and sharing happen when you choose.")
                            Divider()
                            detail("File storage", symbol: "folder",
                                   text: "Imports and exports are stored in Depth Check. iCloud items may need to download before import.")
                        }
                    }
                    .frame(maxWidth: 680)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(DepthCheckTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func detail(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(DepthCheckTheme.accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ModelCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StudioBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(credits)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(22)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Credits & licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(DepthCheckTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var credits: String {
        if let url = Bundle.main.url(forResource: "Model-Licenses", withExtension: "txt", subdirectory: "DepthCheckResources")
            ?? Bundle.main.url(forResource: "Model-Licenses", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return "Depth Anything 3 Base\nDepth Anything 3 research team. Core ML conversion credits and license notices are included with this release's source code.\n\nDepth Anything V2 Small\nDepth Anything V2 research team and Apple's Core ML model distribution.\n\nDepth Check uses these models to estimate scene depth. It synthesizes stereo views from a single source and does not recover a second original camera recording."
    }
}
