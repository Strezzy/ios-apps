import SwiftUI

@main
struct DepthCheckApp: App {
    @StateObject private var store = StudioStore()
    var body: some Scene {
        WindowGroup {
            DepthCheckRootView()
                .environmentObject(store)
                .tint(Color(red: 0.30, green: 0.91, blue: 0.87))
                .preferredColorScheme(.dark)
        }
    }
}
