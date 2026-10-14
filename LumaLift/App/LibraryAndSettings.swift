import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var deleting: LibraryItem?
    var body: some View {
        NavigationStack {
            ZStack {
                Atmosphere()
                if store.library.isEmpty {
                    ContentUnavailableView("Your finished videos", systemImage: "square.stack.3d.up",
                        description: Text("Verified exports appear here. Your originals stay untouched."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(store.library) { item in
                                NavigationLink { ExportDetail(item: item) } label: {
                                    LiftCard {
                                        HStack(spacing: 16) {
                                            Image(systemName: "play.rectangle.fill").font(.largeTitle).foregroundStyle(Palette.gradient)
                                                .frame(width: 54, height: 64)
                                            VStack(alignment: .leading, spacing: 7) {
                                                Text(item.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                                                Text("\(item.dimensions) · \(item.fps)").font(.caption).foregroundStyle(.secondary)
                                                Text(item.created, format: .dateTime.month(.abbreviated).day().hour().minute())
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                                        }
                                    }
                                }.buttonStyle(.plain).contextMenu {
                                    ShareLink(item: item.url)
                                    Button("Delete export", systemImage: "trash", role: .destructive) { deleting = item }
                                }
                            }
                        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }
                }
            }.navigationTitle("Library")
                .confirmationDialog("Delete this export?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete export", role: .destructive) { if let item = deleting { store.remove(item) }; deleting = nil }
                } message: { Text("Only LumaLift’s exported copy will be deleted. The original is not affected.") }
        }
    }
}
struct ExportDetail: View {
    let item: LibraryItem
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ZStack {
            Atmosphere()
            ScrollView {
                VStack(spacing: 20) {
                    PlayerSurface(url: item.url).frame(height: 290).clipShape(.rect(cornerRadius: 24))
                    LiftCard {
                        Text(item.title).font(.title3.bold())
                        LabeledContent("Resolution", value: item.dimensions)
                        LabeledContent("Frame rate", value: item.fps)
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                        LabeledContent("Verified frames", value: "\(item.frames)")
                        Text(item.settings.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                            .buttonStyle(.glassProminent)
                        Button { Task { await store.saveToPhotos(item.url) } } label: {
                            Label("Save", systemImage: "photo.badge.arrow.down").frame(maxWidth: .infinity)
                        }.buttonStyle(.glass)
                    }.controlSize(.large)
                    if let notice = store.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
                    DisclosureGroup("File verification") {
                        Text("SHA-256\n" + item.sha256).font(.caption.monospaced()).textSelection(.enabled).padding(.top, 8)
                    }.font(.subheadline).padding(20).background(.thinMaterial, in: .rect(cornerRadius: 22))
                }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            ZStack {
                Atmosphere()
                ScrollView {
                    VStack(spacing: 20) {
                        LiftCard {
                            HStack(spacing: 16) {
                                Image("BrandMark").resizable().frame(width: 68, height: 68).clipShape(.rect(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("LumaLift").font(.title2.bold())
                                    Text("Private video enhancement").font(.callout).foregroundStyle(.secondary)
                                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        LiftCard {
                            Toggle(isOn: $store.settings.gentleProcessing) {
                                Label("Gentle processing", systemImage: "thermometer.low").font(.headline)
                            }
                            Text("Pause when the phone gets hot. Critical temperatures always pause processing, even when this setting is off.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text("Changing this setting affects your next export.").font(.caption).foregroundStyle(.secondary)
                        }
                        LiftCard {
                            Label("Included AI models", systemImage: "cpu").font(.headline)
                            LabeledContent("Detail", value: "Real-ESRGAN General")
                            LabeledContent("Motion", value: "RIFE 4.26")
                            Text("Both models are bundled with the app. There is no first-launch model download.")
                                .font(.callout).foregroundStyle(.secondary)
                            Divider()
                            Text("Same-size enhancement restores tiles and downsamples them to 1×. Upscaling uses the same AI at 2× or 4×. Turning enhancement off keeps AI upscaling at a lighter fixed strength.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        LiftCard {
                            Label("First-release limits", systemImage: "info.circle").font(.headline)
                            Text("Standard-color SDR videos only. Output up to 3840 × 2160, including portrait. AI motion accepts input up to 1080p. New frame-rate choices are 30 and 60 FPS.")
                            Text("The app exports high-bitrate H.264 MOV files. Original audio is retained when enabled. Enhancement can invent fine detail, and fast movement can produce artifacts; try the preview first.")
                            Text("Physical iPhone performance and long-export reliability still need device testing. No real-time speed is promised.")
                        }.font(.callout)
                        NavigationLink { PrivacyView(embedded: true) } label: {
                            Label("Privacy and open-source notices", systemImage: "lock.shield").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.glass)
                    }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Settings")
        }
    }
}
struct PrivacyView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    private var content: some View {
        ZStack {
            Atmosphere()
            ScrollView {
                VStack(spacing: 20) {
                    LiftCard {
                        Label("Your videos stay yours", systemImage: "lock.shield").font(.title2.bold())
                        Text("LumaLift has no accounts, analytics, advertising SDKs, remote processing or app-initiated network requests. Enhancement and interpolation run on this device.")
                        Text("Imported originals are copied to a private working folder. Finished exports stay in the local app library, excluded from device backups, until you explicitly save or share them. Originals are never edited or deleted.")
                    }
                    LiftCard {
                        Text("System services are your choice").font(.headline)
                        Text("Photos and Files may fetch cloud-hosted originals through Apple or your file provider. To work entirely offline, choose videos already downloaded to your phone. Saving to an iCloud-enabled Photos library or a cloud Files folder may sync the exported copy through that service.")
                        Text("This is a video editor, not an anonymizer. Visible faces, locations, voices and other identifying content remain in your video.")
                    }
                    LiftCard {
                        Text("Open-source acknowledgments").font(.headline)
                        Text("Real-ESRGAN: BSD 3-Clause. RifeMetal: Apache 2.0. Practical-RIFE weights: MIT. The complete license texts are included below.")
                        DisclosureGroup("License texts") {
                            Text((try? String(contentsOf: Bundle.main.url(forResource: "ThirdParty", withExtension: "txt") ?? URL(fileURLWithPath: "/nonexistent"), encoding: .utf8)) ?? "See the source release for notices.")
                                .font(.caption).textSelection(.enabled).padding(.top, 10)
                        }
                    }
                }.font(.callout).padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
    var body: some View {
        if embedded { content }
        else {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }
}
