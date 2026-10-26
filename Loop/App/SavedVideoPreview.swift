import SwiftUI
import AVKit

struct SavedVideoPreview: View {
    let url: URL
    @State private var player = AVPlayer()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                if !reduceMotion { player.play() }
            }
            .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
            .onChange(of: phase) { _, value in if value != .active { player.pause() } }
            .onChange(of: reduceMotion) { _, value in if value { player.pause() } }
    }
}
