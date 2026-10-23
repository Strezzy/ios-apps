import SwiftUI
import SpriteKit

@main struct MoonwakeApp: App {
    @StateObject private var store: GameStore
    private let scene: GameScene

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting = arguments.contains("--ui-testing")
        let repository = isTesting ? SaveRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MoonwakeUITests")) : SaveRepository()
        if isTesting, arguments.contains("--reset-save") { try? FileManager.default.removeItem(at: repository.directory) }
        let model = GameStore(repository: repository, audioEnabled: !isTesting)
        let world = GameScene(store: model)
        model.scene = world
        _store = StateObject(wrappedValue: model)
        scene = world
        #if DEBUG
        if let index = arguments.firstIndex(of: "--realm"), arguments.count > index + 1, let number = Int(arguments[index + 1]), let realm = Realm(rawValue: number) {
            model.hasSave = true; model.progress.unlockedRealm = number; model.progress.realm = number
            world.begin(realm: realm); model.mode = .playing
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            GameRootView(store: store, scene: scene)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true; store.services.startMusic() }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
}
