import SwiftUI
import AVKit
import PhotosUI

@main struct LumaLiftApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Palette.purple)
                .onChange(of: scenePhase) { _, value in store.setBackground(value == .background) }
        }
    }
}

enum Palette {
    static let pink = Color(red: 0.94, green: 0.44, blue: 0.70)
    static let purple = Color(red: 0.57, green: 0.36, blue: 0.88)
    static let ink = Color(red: 0.22, green: 0.13, blue: 0.35)
    static let gradient = LinearGradient(colors: [pink, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
}
struct Atmosphere: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.07, green: 0.045, blue: 0.105) : Color(red: 0.99, green: 0.965, blue: 0.995))
            VStack {
                HStack {
                    Circle().fill(Palette.pink.opacity(0.20)).frame(width: 270, height: 270).blur(radius: 75).offset(x: -60, y: -100)
                    Spacer()
                }
                Spacer()
                Circle().fill(Palette.purple.opacity(0.18)).frame(width: 340, height: 340).blur(radius: 85).offset(x: 100, y: 70)
            }
        }.ignoresSafeArea()
    }
}
struct LiftCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.25), lineWidth: 0.7) }
    }
}
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView {
            Tab("Enhance", systemImage: "wand.and.stars") { EnhanceView() }
            Tab("Library", systemImage: "square.stack.3d.up") { LibraryView() }
            Tab("Settings", systemImage: "slider.horizontal.3") { SettingsView() }
        }
        .alert("Lucid", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .fullScreenCover(isPresented: Binding(get: { store.working }, set: { _ in })) {
            ProcessingView().environmentObject(store).interactiveDismissDisabled()
        }
    }
}
struct EnhanceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showPrivacy = false
    @State private var showResult = false
    var body: some View {
        NavigationStack {
            ZStack {
                Atmosphere()
                ScrollView {
                    VStack(spacing: 22) {
                        if let clip = store.clip {
                            LiftCard {
                                PlayerSurface(url: showResult ? (store.resultURL ?? clip.url) : clip.url)
                                    .frame(height: 220).clipShape(.rect(cornerRadius: 18))
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(clip.title).font(.headline).lineLimit(2)
                                        Text("\(clip.dimensions) · \(String(format: "%.2f", clip.fps)) FPS · \(clip.durationLabel)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if store.resultURL != nil {
                                        Button { showResult.toggle() } label: {
                                            Image(systemName: showResult ? "arrow.uturn.backward" : "sparkles")
                                        }.buttonStyle(.glass)
                                            .accessibilityLabel(showResult ? "Show original video" : "Show processed video")
                                    }
                                }
                                if store.resultURL != nil {
                                    Text(showResult ? (store.resultIsPreview ? "Enhanced preview · 2 seconds" : "Enhanced export") : "Original video")
                                        .font(.caption).foregroundStyle(Palette.purple)
                                }
                            }
                            controls
                            if let warning = store.validationError {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(.orange).padding(.horizontal, 6)
                            }
                            exportControls
                            importControls
                        } else {
                            introduction
                            importControls
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield").foregroundStyle(Palette.purple)
                                Text("No accounts. No uploads. No tracking.")
                            }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                        }
                        if store.importing { ProgressView("Importing video…").padding() }
                        if let notice = store.notice {
                            Label(notice, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                        }
                        if let url = store.resultURL {
                            LiftCard {
                                Label(store.resultIsPreview ? "Preview ready" : "Your video is ready", systemImage: "checkmark.seal")
                                    .font(.headline).foregroundStyle(Palette.purple)
                                HStack {
                                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
                                    Button { Task { await store.saveToPhotos(url) } } label: {
                                        Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                                    }.buttonStyle(.glass)
                                }
                            }
                        }
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
                        .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Lucid")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPrivacy = true } label: { Image(systemName: "lock.shield") }
                        .accessibilityLabel("Privacy and processing details")
                }
            }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let files): if let url = files.first { Task { await store.importFile(url) } }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await store.importPhoto(item); selection = nil; showResult = false }
            }
            .onChange(of: store.resultURL) { _, value in if value != nil { showResult = true } }
        }
    }
    private var introduction: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 44).fill(Palette.gradient.opacity(0.16))
                    .frame(width: 164, height: 164).rotationEffect(.degrees(-10))
                Image("BrandMark").resizable().frame(width: 142, height: 142)
                    .clipShape(.rect(cornerRadius: 34)).shadow(color: Palette.purple.opacity(0.18), radius: 22, y: 12)
            }.accessibilityHidden(true).padding(.top, 24)
            VStack(spacing: 12) {
                Text("A little clearer.\nA lot smoother.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Text("Enhance detail, increase resolution,\nor make motion smoother. All on your iPhone.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                feature("Detail", icon: "sparkles")
                feature("2× / 4×", icon: "arrow.up.left.and.arrow.down.right")
                feature("60 FPS", icon: "waveform.path")
            }.padding(.bottom, 6)
        }.padding(.bottom, 10)
    }
    private func feature(_ name: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(Palette.gradient)
            Text(name).font(.caption.weight(.medium))
        }.frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }
    private var importControls: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selection, matching: .videos, preferredItemEncoding: .current) {
                Label(store.clip == nil ? "Choose video" : "Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.glassProminent)
            Button { showFiles = true } label: {
                Image(systemName: "folder").font(.title3).padding(.vertical, 8).padding(.horizontal, 10)
            }.buttonStyle(.glass).accessibilityLabel("Import video from Files")
        }.disabled(store.importing || store.working)
    }
    private var controls: some View {
        VStack(spacing: 16) {
            LiftCard {
                Toggle(isOn: $store.settings.enhance) {
                    Label("AI enhancement", systemImage: "sparkles").font(.headline)
                }
                Text("Restore detail and reduce noise without having to change the resolution.")
                    .font(.callout).foregroundStyle(.secondary)
                if store.settings.enhance {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Strength").font(.subheadline)
                            Spacer()
                            Text("\(Int(store.settings.strength * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Slider(value: $store.settings.strength, in: 0...1, step: 0.05).accessibilityLabel("Enhancement strength")
                        HStack { Text("Natural"); Spacer(); Text("More detail") }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LiftCard {
                HStack {
                    Label("Resolution", systemImage: "arrow.up.left.and.arrow.down.right").font(.headline)
                    Spacer()
                    Picker("Output resolution", selection: $store.settings.scale) {
                        Text("Original (1×)").tag(1)
                        Text("2× upscale").tag(2)
                        Text("4× upscale").tag(4)
                    }.labelsHidden().pickerStyle(.menu)
                }
                Text(store.outputDimensions).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Label("Frame rate", systemImage: "waveform.path").font(.headline)
                    Spacer()
                    Picker("Output frame rate", selection: $store.settings.fps) {
                        Text("Original").tag(0)
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                    }.labelsHidden().pickerStyle(.menu)
                }
                Text(store.settings.fps == 0 ? "Keep the original frame timing." : "AI creates intermediate frames. Playback speed and duration stay the same.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                Toggle(isOn: $store.settings.preserveAudio) {
                    Label("Keep original audio", systemImage: "speaker.wave.2").font(.subheadline)
                }
            }
        }
    }
    private var exportControls: some View {
        VStack(spacing: 12) {
            Button { store.start(preview: false) } label: {
                Label("Enhance video", systemImage: "sparkles").font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.glassProminent)
            Button { store.start(preview: true) } label: {
                Label("Try a 2-second preview", systemImage: "play.circle").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.glass)
            Text("Originals are never overwritten. Keep Lucid open while processing.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.disabled(store.validationError != nil || store.importing)
    }
}
struct PlayerSurface: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
            .onChange(of: url) { _, value in player?.pause(); player = AVPlayer(url: value) }
            .onDisappear { player?.pause(); player = nil }
    }
}
struct ProcessingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmCancel = false
    var body: some View {
        ZStack {
            Atmosphere()
            VStack(spacing: 30) {
                Spacer()
                ZStack {
                    Circle().stroke(Palette.purple.opacity(0.12), lineWidth: 14)
                    Circle().trim(from: 0, to: max(0.01, store.progress.fraction))
                        .stroke(Palette.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: store.progress.fraction)
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.title).foregroundStyle(Palette.gradient)
                        Text("\(Int(store.progress.fraction * 100))%")
                            .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                }.frame(width: 220, height: 220).padding(12)
                VStack(spacing: 10) {
                    Text(store.paused ? "Paused" : store.progress.stage).font(.title2.bold()).multilineTextAlignment(.center)
                    Text("\(store.progress.frames) frames processed").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text("Everything is happening on your device.\nKeep this app open; processing pauses when needed.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
                }
                Spacer()
                Button { store.togglePause() } label: {
                    Label(store.paused ? "Resume" : "Pause", systemImage: store.paused ? "play.fill" : "pause.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.glassProminent)
                Button("Cancel export", role: .destructive) { confirmCancel = true }.buttonStyle(.glass)
            }.padding(32)
        }.confirmationDialog("Cancel this export?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel export", role: .destructive) { store.cancel() }
            Button("Keep processing", role: .cancel) {}
        } message: { Text("The unfinished output will be removed. Your original video is safe.") }
    }
}
