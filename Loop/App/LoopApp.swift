import SwiftUI
import PhotosUI

@main struct LoopApp: App {
    @StateObject private var store = LoopStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            LoopRootView().environmentObject(store).tint(LoopTheme.teal)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onChange(of: scenePhase) { _, phase in store.setActive(phase == .active) }
        }
    }
}

struct LoopRootView: View {
    @EnvironmentObject private var store: LoopStore
    var body: some View {
        TabView {
            Tab("Create", systemImage: "plus.circle") { CreateView() }
            Tab("Library", systemImage: "square.stack") { LoopLibraryView() }
            Tab("Settings", systemImage: "slider.horizontal.3") { LoopSettingsView() }
        }
        .sheet(item: $store.editingProject) { project in
            EditorView(project: project).environmentObject(store)
        }
        .alert("Loop", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .task { await store.prepareUITestFixtureIfNeeded() }
    }
}

struct CreateView: View {
    @EnvironmentObject private var store: LoopStore
    @State private var selection: PhotosPickerItem?
    @State private var filesPresented = false
    var body: some View {
        NavigationStack {
            ZStack {
                LoopAtmosphere()
                ScrollView {
                    VStack(spacing: 28) {
                        hero
                        importCard
                        if store.importing { ProgressView("Importing your video…").padding().accessibilityIdentifier("importProgress") }
                        if !store.projects.isEmpty { recentProjects }
                        HStack(spacing: 7) {
                            Image(systemName: "lock.shield")
                            Text("Your moments stay yours.")
                        }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 22)
                    }.padding(.horizontal, 22).padding(.top, 18).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Loop")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("ON DEVICE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5)
                        .foregroundStyle(LoopTheme.teal).padding(.horizontal, 11).padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityLabel("All processing is on device")
                }
            }
            .fileImporter(isPresented: $filesPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await store.importFile(url) } }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await store.importPhoto(item); selection = nil }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 22) {
            LoopMark(size: 124).rotationEffect(.degrees(-7)).padding(.vertical, 12)
            VStack(spacing: 11) {
                Text("A moment.\nOn repeat.")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .tracking(-1.5).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text("Beautiful GIFs, made right here.\nFrame it. Make it yours. Let it loop.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(3)
            }
            HStack(spacing: 10) {
                feature("4K detail", "viewfinder")
                feature("Motion tracking", "scope")
                feature("Entirely local", "iphone")
            }
        }
    }

    private func feature(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title3).foregroundStyle(LoopTheme.teal)
            Text(title).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(.thinMaterial, in: .rect(cornerRadius: 19))
    }

    private var importCard: some View {
        LoopCard {
            EditorSectionTitle(title: "Start with a video", subtitle: "From a quick reaction to a little cinematic loop.")
            HStack(spacing: 12) {
                PhotosPicker(selection: $selection, matching: .videos, preferredItemEncoding: .current) {
                    Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.glassProminent).accessibilityIdentifier("importPhotos")
                Button { filesPresented = true } label: {
                    Label("Files", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.glass).accessibilityIdentifier("importFiles")
            }.disabled(store.importing)
            Text("Use a downloaded video for offline import. Formats depend on your iPhone’s video support.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pick up where you left off").font(.headline)
                Spacer()
            }
            ForEach(Array(store.projects.prefix(3))) { project in
                Button { store.editingProject = project } label: {
                    ProjectRow(project: project, thumbnailURL: store.projectThumbnail(project))
                }.buttonStyle(.plain).accessibilityIdentifier("project-\(project.name)")
            }
        }
    }
}

struct ProjectRow: View {
    let project: LoopProject
    let thumbnailURL: URL
    var body: some View {
        HStack(spacing: 15) {
            LocalThumbnail(url: thumbnailURL).frame(width: 74, height: 74).clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(project.name).font(.headline).lineLimit(1)
                Text("\(project.metadata.size.label) · \(LoopFormat.rate(project.metadata.nominalFrameRate)) FPS")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(LoopFormat.time(project.duration)) selected").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(LoopTheme.teal)
        }.padding(12).background(.regularMaterial, in: .rect(cornerRadius: 24))
            .contentShape(Rectangle())
    }
}

struct LocalThumbnail: View {
    var url: URL?
    var body: some View {
        ZStack {
            Rectangle().fill(LoopTheme.gradient.opacity(0.2))
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "play.rectangle").font(.title2).foregroundStyle(LoopTheme.teal)
            }
        }.clipped().accessibilityHidden(true)
    }
}
