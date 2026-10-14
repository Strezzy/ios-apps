import SwiftUI
import UIKit

@main struct RiftApp: App {
    @StateObject private var model=AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ChatView().environmentObject(model).tint(RiftTheme.accent)
                .overlay { if phase != .active { RiftBackground().overlay { VStack(spacing:16) { RiftMark().frame(width:64,height:80); Text("Rift").font(.title.bold()); Text("Private conversation").foregroundStyle(.secondary) } }.ignoresSafeArea() } }
                .onChange(of:phase) { _, value in if value == .background { model.background() } }
                .onReceive(NotificationCenter.default.publisher(for:ProcessInfo.thermalStateDidChangeNotification)) { _ in model.thermalChanged() }
                .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)) { _ in model.lowMemory() }
        }
    }
}
