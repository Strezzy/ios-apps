import SwiftUI

struct StudioSettingsView: View {
    @EnvironmentObject private var store: StudioStore
    @State private var showFormats = false
    @State private var showCredits = false
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "Make it your perspective")
                        Text("Fine-tune the feeling.")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .tracking(-0.8)
                        Text("A few thoughtful controls. Your original resolution and frame timing are always kept.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    Text("Depth Check · \(appVersion)")
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
                Eyebrow(text: "Depth intelligence", symbol: "cpu")
                modelOption(.detailed, title: "Detailed", modelName: "Depth Anything 3 · Base", detail: "A larger, newer depth model. Uses more memory and takes longer to process.")
                Divider()
                modelOption(.balanced, title: "Balanced", modelName: "Depth Anything V2 · Small", detail: "Apple's smaller Core ML model package. A lighter option for long videos.")
                InfoNote(text: "Both models are included and run on your iPhone. Depth is estimated at the model's working size, then used to render views at your original pixel dimensions.")
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
                Eyebrow(text: "Depth & perspective", symbol: "view.3d")
                SettingRow("Screen plane", subtitle: "Choose the depth that rests on the screen. Other parts of the scene appear in front of or behind it.") {
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
                        Text("For 3D viewers that expect the opposite eye order.")
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
                        Text("Extra memory cleanup while processing. Useful for long, high-resolution videos; may take longer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(isOn: $store.options.temporalStability) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Steadier video depth").font(.headline)
                        Text("Smooths sudden depth changes between frames to help reduce flicker.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle(isOn: $store.options.preserveAudio) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keep original audio").font(.headline)
                        Text("Include the source video's audio in your exports.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                InfoNote(text: "Video is always processed one frame at a time. Memory saver also releases rendering caches every 24 frames; it keeps the original frame timing.", symbol: "memorychip")
            }
            .tint(DepthCheckTheme.accent)
            .disabled(store.isBusy)
        }
    }

    private var outputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 19) {
                Eyebrow(text: "Export preferences", symbol: "square.and.arrow.up")
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
                SettingRow("Photo file type", subtitle: store.options.format == .spatial ? "Apple Spatial photos always use stereo HEIC. This preference applies to other photo exports." : "Choose the file type for rendered photos. PNG stores pixels losslessly; HEIC and JPEG use high-quality compression.") {
                    Picker("Photo file type", selection: $store.options.photoEncoding) {
                        ForEach(PhotoEncoding.allCases) { format in Text(format.title).tag(format) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(store.options.format == .spatial)
                }
                InfoNote(text: "Videos export as HEVC in MOV files. HDR is tone-mapped to SDR in this version. Source dimensions and frame timing are preserved.")
                InfoNote(text: "An output size your iPhone's encoder cannot handle produces a clear error. Separate eye files can be a practical option for very large sources.", symbol: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(store.isBusy)
        }
    }

    private var privacyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Your media stays with you.", systemImage: "lock.shield")
                    .font(.headline)
                    .foregroundStyle(DepthCheckTheme.accent)
                Text("Depth estimation and rendering run locally. Both models are bundled with the app. Photos and videos are shared or saved to your photo library only when you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

struct ModelCreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StudioBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Built on open depth research.")
                            .font(.title2.weight(.semibold))
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
