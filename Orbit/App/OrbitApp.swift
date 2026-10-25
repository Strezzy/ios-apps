import SwiftUI

@main struct OrbitApp: App {
    @StateObject private var library = MediaLibrary()
    @AppStorage("orbit.appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            OrbitLibraryView()
                .environmentObject(library)
                .tint(OrbitTheme.blue)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onOpenURL { library.importFile($0) }
        }
    }
}
