import SwiftUI
import UIKit
import Combine

@main
struct VelvetApp: App {
    @UIApplicationDelegateAdaptor(VelvetAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(model.vault)
                .preferredColorScheme(.dark).tint(VelvetTheme.accent)
                .background(SystemPrivacyShield().frame(width: 0, height: 0))
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let vault: VaultStore
    let camera: CameraController
    let search = LocalSearchService()
    @Published var tab = 0
    @Published var error: String?
    @Published var busy = false
    @Published var indexing = false
    @Published var concealed = false
    @Published private(set) var activeSearches = 0
    private var generation = UUID()
    private var resetTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    var sessionID: UUID { generation }
    var aiBusy: Bool { indexing || activeSearches > 0 }
    init() {
        let vault = VaultStore()
        self.vault = vault
        camera = CameraController(vault: vault)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.concealed = true }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
        observers.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
        observers.append(center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if UIScreen.main.isCaptured { self?.lock() } }
        })
    }
    func unlock() async {
        guard !busy, !UIScreen.main.isCaptured else { return }
        let expected = generation
        busy = true
        defer { busy = false }
        await resetTask?.value
        guard expected == generation else { return }
        do {
            try await vault.unlock()
            guard expected == generation, vault.isUnlocked else { return }
            concealed = false
        } catch {
            guard expected == generation else { return }
            self.error = "Velvet couldn’t unlock. Use Face ID or your iPhone passcode, then try again. Your photos and videos have been preserved."
        }
    }
    func lock() {
        generation = UUID(); concealed = true
        camera.stop(); vault.lock()
        resetTask = Task { await search.reset() }
    }
    func beginSearch() { activeSearches += 1 }
    func endSearch() { activeSearches = max(0, activeSearches - 1) }
    func perform(_ action: @escaping () async throws -> Void) {
        Task { do { try await action() } catch { self.error = error.localizedDescription } }
    }
    func index(_ id: UUID) async {
        let expected = generation
        guard vault.isUnlocked, tab != 0, !camera.isRecording, !camera.isCapturing, !indexing,
              !Task.isCancelled, let item = vault.items.first(where: { $0.id == id }), item.trashedAt == nil else { return }
        indexing = true
        defer { indexing = false }
        do {
            let data: Data
            if item.kind == .video { guard let cover = try await vault.thumbnail(for: id) else { return }; data = cover }
            else { data = try await vault.original(for: id) }
            guard expected == generation, vault.isUnlocked, tab != 0,
                  !camera.isRecording, !camera.isCapturing, !Task.isCancelled else { return }
            let doc = try await search.analyze(imageData: data, itemID: id, mediaKind: item.kind == .video ? "video" : "photo")
            guard generation == expected, vault.isUnlocked, !Task.isCancelled else { return }
            try await vault.saveSearchDocument(doc)
        } catch { /* Indexing is optional; original media remains available. */ }
    }
    func reindex(onlyMissing: Bool = false) async {
        let expected = generation
        guard vault.isUnlocked, tab != 0, !camera.isRecording, !camera.isCapturing, !Task.isCancelled else { return }
        var completed = Set<UUID>()
        if onlyMissing {
            do {
                let documents = try await vault.searchDocuments()
                completed = Set(documents.filter {
                    $0.schemaVersion == SearchDocument.currentSchemaVersion &&
                    (!LocalSearchService.modelIsBundled || $0.modelIdentifier == LocalSearchService.modelIdentifier)
                }.map(\.id))
            } catch { return }
        }
        for item in vault.items where item.trashedAt == nil {
            guard expected == generation, vault.isUnlocked, tab != 0,
                  !camera.isRecording, !camera.isCapturing, !Task.isCancelled else { break }
            if completed.contains(item.id) { continue }
            await index(item.id)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if vault.isUnlocked {
                Group {
                    if model.tab == 0 { CameraScreen(controller: model.camera) }
                    else { GalleryScreen() }
                }
                .onChange(of: model.tab) { _, value in
                    InterfaceOrientation.update(cameraIsVisible: value == 0)
                    if value != 0 {
                        model.camera.stop()
                        Task { await model.reindex(onlyMissing: true) }
                    }
                }
            } else { LockScreen() }
            if model.concealed || UIScreen.main.isCaptured {
                PrivacyCover().ignoresSafeArea().transition(.identity)
            }
        }
        .onAppear { InterfaceOrientation.update(cameraIsVisible: !vault.isUnlocked || model.tab == 0) }
        .onChange(of: phase) { _, phase in
            switch phase {
            case .active:
                model.concealed = UIScreen.main.isCaptured
                InterfaceOrientation.update(cameraIsVisible: !vault.isUnlocked || model.tab == 0)
            case .inactive: model.concealed = true
            case .background: model.lock()
            @unknown default: model.lock()
            }
        }
        .alert("Velvet", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: vault.isUnlocked) { _, unlocked in
            InterfaceOrientation.update(cameraIsVisible: !unlocked || model.tab == 0)
            if unlocked { Task { await model.reindex(onlyMissing: true) } }
        }
    }
}

struct LockScreen: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image("Brand").resizable().frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 23)).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Velvet").font(.system(size: 42, weight: .light, design: .serif))
            }
            Spacer()
            VStack(spacing: 18) {
                Button { Task { await model.unlock() } } label: {
                    HStack(spacing: 12) {
                        if model.busy { ProgressView() } else { Image(systemName: "faceid") }
                        Text(model.busy ? "Unlocking…" : "Unlock Velvet").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.glassProminent).disabled(model.busy)
                Text("Use Face ID or your iPhone passcode.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.bottom, 38)
        }.padding(.horizontal, 36)
            .background(LinearGradient(colors: [Color(red: 0.13, green: 0.04, blue: 0.08), .black, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack { Color.black; VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(VelvetTheme.accent)
            Text("Velvet").font(.system(.title, design: .serif))
        } }.accessibilityLabel("Velvet locked")
    }
}
