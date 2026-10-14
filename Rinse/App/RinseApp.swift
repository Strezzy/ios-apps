import SwiftUI

@main struct RinseApp: App {
    @StateObject private var store = RinseStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RinseView(store: store)
                .tint(RinseTheme.accent)
                .overlay {
                    if phase == .background {
                        ZStack {
                            Color(.systemBackground).ignoresSafeArea()
                            Label("Veil", systemImage: "lock.shield").font(.title)
                        }
                    }
                }
                .onChange(of: phase) { _, value in
                    if value == .background && store.busy {
                        store.cancel()
                        store.message = "Processing stops when Rinse goes into the background. Keep the app open while cleaning, then retry any cancelled items."
                    }
                }
                .onOpenURL { url in store.importFiles([url]) }
        }
    }
}
