import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct OrbitLibraryView: View {
    @EnvironmentObject private var library: MediaLibrary
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showSettings = false
    @State private var deletingVideo: OrbitVideo?
    @State private var renamingVideo: OrbitVideo?
    @State private var newName = ""
    @State private var renamePresented = false
    @State private var deletePresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                OrbitAtmosphere()
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        header
                        if library.videos.isEmpty { welcome }
                        importControls
                        if !library.videos.isEmpty { recentVideos }
                        else {
                            Label("Your videos stay on your device", systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.top, 3)
                        }
                    }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 30)
                        .frame(maxWidth: 920).frame(maxWidth: .infinity)
                }
                if library.isImporting { importingOverlay }
            }
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("orbit.home")
        }
        .sheet(isPresented: $showPhotos) {
            OrbitPhotoPicker(onSelect: { library.importProvider($0) }, onDismiss: { showPhotos = false })
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { library.importFile(url) }
            case .failure(let error): library.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showSettings) { OrbitSettingsView().environmentObject(library) }
        .fullScreenCover(item: $library.selectedVideo) { video in
            OrbitPlayerView(video: video, url: library.videoURL(video))
        }
        .alert("Orbit", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .alert("Rename video", isPresented: $renamePresented) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renamingVideo = nil }
            Button("Save") { if let video = renamingVideo { library.rename(video, to: newName) }; renamingVideo = nil }
        }
        .confirmationDialog("Remove this video from Orbit?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Remove local copy", role: .destructive) { if let video = deletingVideo { library.delete(video) }; deletingVideo = nil }
            Button("Cancel", role: .cancel) { deletingVideo = nil }
        } message: {
            Text("Only Orbit’s imported copy will be removed. The original in Photos or Files stays where it is.")
        }
    }

    private var header: some View {
        HStack(spacing: 15) {
            OrbitMark(size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("Orbit").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A new perspective").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.body.weight(.semibold)).frame(width: 30, height: 34)
            }.buttonStyle(.glass).accessibilityLabel("Settings").accessibilityIdentifier("orbit.settings")
        }.padding(.top, 8)
    }

    private var welcome: some View {
        OrbitCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 26) {
                    OrbitDepthArtwork().frame(width: 245, height: 170)
                    welcomeWords.frame(minWidth: 260, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    OrbitDepthArtwork().frame(height: 165).frame(maxWidth: .infinity)
                    welcomeWords
                }
            }
        }
    }

    private var welcomeWords: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your memories,\nwith dimension.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Open a spatial video. Tilt your iPhone to look around, or drag the picture to explore.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                Text("Portrait or landscape. Full screen.")
            }.font(.caption.weight(.medium)).foregroundStyle(OrbitTheme.blue).padding(.top, 4)
        }
    }

    private var importControls: some View {
        HStack(spacing: 12) {
            Button { showPhotos = true } label: {
                VStack(spacing: 9) {
                    Image(systemName: "photo.on.rectangle.angled").font(.title2)
                    Text("Photos").font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }.buttonStyle(.glassProminent).tint(OrbitTheme.blue)
                .accessibilityLabel("Open video from Photos").accessibilityIdentifier("orbit.import.photos")
            Button { showFiles = true } label: {
                VStack(spacing: 9) {
                    Image(systemName: "folder").font(.title2)
                    Text("Files").font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }.buttonStyle(.glass)
                .accessibilityLabel("Open video from Files").accessibilityIdentifier("orbit.import.files")
        }.disabled(library.isImporting)
    }

    private var recentVideos: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Your videos").font(.title2.weight(.bold))
                Spacer()
                Text("\(library.videos.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 154), spacing: 15)], spacing: 19) {
                ForEach(library.videos) { video in
                    Button { library.open(video) } label: {
                        OrbitVideoCard(video: video, thumbnailURL: library.thumbnailURL(video))
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(video.title), \(video.isSpatial ? "spatial video" : "2D video"), \(OrbitFormat.time(video.duration))")
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") { library.open(video) }
                            ShareLink(item: library.videoURL(video)) { Label("Share original video", systemImage: "square.and.arrow.up") }
                            Button("Rename", systemImage: "pencil") { renamingVideo = video; newName = video.title; renamePresented = true }
                            Button("Remove from Orbit", systemImage: "trash", role: .destructive) { deletingVideo = video; deletePresented = true }
                        }
                }
            }
        }
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            VStack(spacing: 18) {
                if let progress = library.importProgress {
                    ProgressView(value: progress).progressViewStyle(.linear).frame(width: 200)
                } else { ProgressView().controlSize(.large) }
                Text(library.importStatus).font(.headline)
                Text("Keeping the original quality.").font(.caption).foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) { library.cancelImport() }.buttonStyle(.glass)
            }.padding(28).frame(maxWidth: 310)
                .background(.regularMaterial, in: .rect(cornerRadius: 28))
                .accessibilityElement(children: .contain)
        }.accessibilityIdentifier("orbit.import.progress")
    }
}

private struct OrbitVideoCard: View {
    let video: OrbitVideo
    let thumbnailURL: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                OrbitThumbnail(url: thumbnailURL)
                    .frame(maxWidth: .infinity).aspectRatio(1.45, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Label(video.isSpatial ? "Spatial" : "2D", systemImage: video.isSpatial ? "cube.transparent" : "rectangle")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: .capsule).padding(9)
                    }
                Text(OrbitFormat.time(video.duration)).font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: .capsule).padding(9)
            }.clipShape(.rect(cornerRadius: 20))
            Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
            Text(video.dimensions).font(.caption2).foregroundStyle(.secondary)
        }.contentShape(.rect)
    }
}

private struct OrbitThumbnail: View {
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OrbitTheme.gradient.opacity(0.20)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "video").font(.largeTitle).foregroundStyle(OrbitTheme.blue.opacity(0.7))
                }
            }
        }.task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
            if !Task.isCancelled { image = loaded }
        }
    }
}

/// Brand artwork for the empty library. This is deliberately abstract, never
/// presented as a playable video or evidence of a recorded spatial effect.
private struct OrbitDepthArtwork: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Ellipse().fill(OrbitTheme.blue.opacity(0.13)).frame(width: 240, height: 50).blur(radius: 23).offset(y: 72)
            RoundedRectangle(cornerRadius: 24).fill(OrbitTheme.violet.opacity(0.10))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(OrbitTheme.violet.opacity(0.20), lineWidth: 1) }
                .frame(width: 205, height: 127).rotationEffect(.degrees(9)).offset(x: 23, y: -14)
            RoundedRectangle(cornerRadius: 24).fill(OrbitTheme.ice.opacity(0.12))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(OrbitTheme.blue.opacity(0.17), lineWidth: 1) }
                .frame(width: 213, height: 135).rotationEffect(.degrees(-8)).offset(x: -18, y: 5)
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.23, blue: 0.48), Color(red: 0.17, green: 0.13, blue: 0.33)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(RadialGradient(colors: [OrbitTheme.ice, OrbitTheme.blue, OrbitTheme.violet.opacity(0.7)], center: .topLeading, startRadius: 0, endRadius: 76))
                    .frame(width: 77, height: 77).offset(x: 15, y: -4)
                    .shadow(color: OrbitTheme.ice.opacity(0.23), radius: 20)
                Ellipse().stroke(LinearGradient(colors: [.white.opacity(0.3), OrbitTheme.ice, .white.opacity(0.85)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: 143, height: 43).rotationEffect(.degrees(-30)).offset(x: 15, y: -3)
                Circle().fill(.white).frame(width: 6, height: 6).offset(x: -75, y: -39)
                Circle().fill(OrbitTheme.ice.opacity(0.7)).frame(width: 3, height: 3).offset(x: 77, y: 42)
                RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.23), lineWidth: 1)
            }.frame(width: 213, height: 137).rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.13), radius: 13, y: 10)
        }.accessibilityHidden(true)
    }
}
