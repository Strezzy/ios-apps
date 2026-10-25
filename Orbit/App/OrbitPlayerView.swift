import SwiftUI
import UIKit

struct OrbitPlayerView: View {
    let video: OrbitVideo
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @StateObject private var player = SpatialPlaybackController()
    @StateObject private var motion = TiltMotionController()
    @AppStorage("orbit.defaultDepth") private var defaultDepth = 0.65
    @AppStorage("orbit.autoLoop") private var autoLoop = true
    @AppStorage("orbit.motionEnabled") private var motionEnabled = true
    @State private var controlsVisible = true
    @State private var optionsPresented = false
    @State private var isScrubbing = false
    @State private var scrubTime = 0.0
    @State private var resumeAfterScrub = false
    @State private var resumeAfterInactive = false
    @State private var hideTask: Task<Void, Never>?
    @State private var originalIdleTimer = false
    @State private var isDraggingPicture = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width > geometry.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                SpatialVideoSurface(player: player, motion: motion)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { toggleControls() }
                    .gesture(DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard player.isSpatial else { return }
                            isDraggingPicture = true
                            let scale = max(100, min(geometry.size.width, geometry.size.height) * 0.38)
                            motion.setManualOffset(CGSize(width: max(-1, min(1, value.translation.width / scale)),
                                                         height: max(-1, min(1, value.translation.height / scale))))
                        }
                        .onEnded { _ in isDraggingPicture = false; motion.clearManualOffset(); scheduleHide() })
                    .accessibilityLabel(player.isSpatial ? "Spatial video" : "Video")
                    .accessibilityHint("Tap to show playback controls. Drag to explore depth.")
                    .accessibilityAction(named: "Show playback controls") { revealControls() }
                    .accessibilityIdentifier("orbit.player")

                if player.isLoading { loading }
                else if let error = player.errorMessage { playbackError(error) }

                if controlsVisible {
                    VStack(spacing: 0) {
                        header(compact: compact)
                        Spacer(minLength: 8)
                        if player.errorMessage == nil {
                            playbackControls(compact: compact)
                                .frame(maxWidth: compact ? 650 : 580)
                        }
                    }.padding(.horizontal, compact ? 22 : 16)
                        .padding(.top, compact ? 8 : 10).padding(.bottom, compact ? 10 : 16)
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(OrbitTheme.ice)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .sheet(isPresented: $optionsPresented, onDismiss: { scheduleHide() }) {
            OrbitPlaybackOptions(player: player, motion: motion)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .task(id: video.id) {
            player.depthStrength = defaultDepth
            player.isLooping = autoLoop
            player.tiltEnabled = motionEnabled && !reduceMotion
            await player.load(url: url)
            guard !Task.isCancelled, scenePhase == .active else { return }
            motion.recenter()
            player.play()
            scheduleHide()
        }
        .onAppear {
            originalIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            hideTask?.cancel(); hideTask = nil
            motion.stop(); player.close()
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
        }
        .onChange(of: player.isPlaying) { _, playing in
            if playing { scheduleHide() }
            else { revealControls() }
        }
        .onChange(of: scenePhase) { previous, phase in
            if phase != .active {
                if previous == .active { resumeAfterInactive = player.isPlaying }
                player.pause(); motion.stop(); hideTask?.cancel()
            } else {
                motion.start(); motion.recenter()
                if resumeAfterInactive { player.play() }
                resumeAfterInactive = false
            }
        }
        .onChange(of: reduceMotion) { _, reduced in if reduced { player.tiltEnabled = false; motion.clearManualOffset() } }
        .onChange(of: voiceOverEnabled) { _, enabled in if enabled { revealControls() } }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                player.pause(); dismiss()
            } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 31, height: 34)
            }.buttonStyle(.glass).tint(.white).accessibilityLabel("Close video").accessibilityIdentifier("orbit.player.close")
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(video.title).font(compact ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
                if !player.isLoading {
                    Label(player.isSpatial ? "Spatial video" : "2D video", systemImage: player.isSpatial ? "cube.transparent" : "rectangle")
                        .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.75))
                }
            }.padding(.horizontal, 13).padding(.vertical, 9)
                .background(.black.opacity(0.35), in: .capsule)
                .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                optionsPresented = true; hideTask?.cancel()
            } label: {
                Image(systemName: "slider.horizontal.3").font(.body.weight(.semibold)).frame(width: 31, height: 34)
            }.buttonStyle(.glass).tint(.white).accessibilityLabel("Playback options").accessibilityIdentifier("orbit.player.options")
        }.foregroundStyle(.white)
    }

    private func playbackControls(compact: Bool) -> some View {
        OrbitGlassPanel {
            VStack(spacing: compact ? 8 : 13) {
                if !compact {
                    HStack {
                        if player.isSpatial {
                            Label(player.depthStatus, systemImage: "cube.transparent")
                                .lineLimit(1)
                        } else {
                            Label("This video plays in 2D", systemImage: "rectangle")
                        }
                        Spacer(minLength: 5)
                        if player.isSpatial {
                            Button {
                                motion.recenter(); revealControls(); scheduleHide()
                            } label: { Label("Recenter", systemImage: "scope") }
                                .accessibilityIdentifier("orbit.player.recenter")
                        }
                    }.font(.caption).foregroundStyle(.white.opacity(0.82))
                }
                timeline
                HStack(spacing: compact ? 22 : 8) {
                    Button {
                        player.tiltEnabled.toggle()
                        if player.tiltEnabled { motion.recenter() }
                        revealControls(); scheduleHide()
                    } label: {
                        Image(systemName: player.tiltEnabled ? "move.3d" : "hand.draw")
                            .font(.title3).frame(width: 38, height: 42)
                            .foregroundStyle(player.tiltEnabled && player.isSpatial ? OrbitTheme.ice : .white.opacity(0.65))
                    }.disabled(!player.isSpatial)
                        .accessibilityLabel(player.tiltEnabled ? "Disable phone tilt" : "Enable phone tilt")
                        .accessibilityIdentifier("orbit.player.tilt")
                    Spacer(minLength: 0)
                    Button {
                        player.seek(to: max(0, player.currentTime - 10)); revealControls(); scheduleHide()
                    } label: { Image(systemName: "gobackward.10").font(.title2).frame(width: 38, height: 44) }
                        .accessibilityLabel("Back ten seconds")
                    Button {
                        player.togglePlayback(); revealControls(); scheduleHide()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 23, weight: .semibold)).frame(width: 57, height: compact ? 44 : 51)
                            .contentTransition(.symbolEffect(.replace))
                    }.buttonStyle(.glassProminent).tint(.white.opacity(0.9)).foregroundStyle(.black)
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play").accessibilityIdentifier("orbit.player.playpause")
                    Button {
                        player.seek(to: min(player.duration, player.currentTime + 10)); revealControls(); scheduleHide()
                    } label: { Image(systemName: "goforward.10").font(.title2).frame(width: 38, height: 44) }
                        .accessibilityLabel("Forward ten seconds")
                    Spacer(minLength: 0)
                    Button {
                        player.isMuted.toggle(); revealControls(); scheduleHide()
                    } label: {
                        Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title3).frame(width: 38, height: 42)
                    }.accessibilityLabel(player.isMuted ? "Unmute" : "Mute")
                }.buttonStyle(.plain).foregroundStyle(.white).disabled(player.isLoading)
            }.padding(.horizontal, 20).padding(.vertical, compact ? 12 : 16)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { isScrubbing ? scrubTime : player.currentTime }, set: {
                scrubTime = $0
                if !isScrubbing { player.seek(to: $0) }
            }),
                   in: 0...max(0.01, player.duration), onEditingChanged: { editing in
                if editing {
                    scrubTime = player.currentTime
                    resumeAfterScrub = player.isPlaying
                    isScrubbing = true
                    player.pause(); hideTask?.cancel()
                } else {
                    player.seek(to: scrubTime)
                    isScrubbing = false
                    if resumeAfterScrub { player.play() }
                    resumeAfterScrub = false
                    scheduleHide()
                }
            }).tint(.white).disabled(player.isLoading || player.duration <= 0)
                .accessibilityLabel("Video position")
                .accessibilityValue("\(OrbitFormat.time(isScrubbing ? scrubTime : player.currentTime)) of \(OrbitFormat.time(player.duration))")
                .accessibilityIdentifier("orbit.player.timeline")
            HStack {
                Text(OrbitFormat.time(isScrubbing ? scrubTime : player.currentTime))
                Spacer()
                Text("−" + OrbitFormat.time(max(0, player.duration - (isScrubbing ? scrubTime : player.currentTime))))
            }.font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.74))
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white).controlSize(.large)
            Text("Opening your video…").font(.subheadline)
        }.foregroundStyle(.white).padding(26).background(.black.opacity(0.48), in: .rect(cornerRadius: 23))
    }

    private func playbackError(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(OrbitTheme.ice)
            Text("Couldn’t play this video").font(.title3.weight(.semibold))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Back to your videos") { dismiss() }.buttonStyle(.glassProminent)
        }.padding(27).frame(maxWidth: 340).background(.regularMaterial, in: .rect(cornerRadius: 27))
    }

    private func revealControls() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { controlsVisible = true }
    }
    private func toggleControls() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }
    private func scheduleHide() {
        hideTask?.cancel()
        guard player.isPlaying, !isScrubbing, !optionsPresented, !voiceOverEnabled, !isDraggingPicture else { return }
        hideTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, player.isPlaying, !isScrubbing, !optionsPresented, !voiceOverEnabled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { controlsVisible = false }
        }
    }
}

private struct OrbitPlaybackOptions: View {
    @ObservedObject var player: SpatialPlaybackController
    @ObservedObject var motion: TiltMotionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if player.isSpatial {
                    Section {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Strength")
                                Spacer()
                                Text("\(Int(player.depthStrength * 100))%").foregroundStyle(.secondary).monospacedDigit()
                            }
                            Slider(value: $player.depthStrength, in: 0...1).accessibilityLabel("Depth strength")
                        }.padding(.vertical, 5)
                        Toggle("Tilt to look around", isOn: $player.tiltEnabled)
                        Button {
                            motion.recenter()
                        } label: { Label("Recenter at this angle", systemImage: "scope") }
                    } header: {
                        Text("Depth")
                    } footer: {
                        Text(motion.available ? "Hold the phone comfortably, then recenter. You can also drag the picture to explore." : "Motion isn’t available here. Drag the picture to explore depth.")
                    }
                }
                Section("Playback") {
                    Toggle("Fill screen", isOn: $player.fillScreen)
                    Toggle("Loop video", isOn: $player.isLooping)
                    Toggle("Mute audio", isOn: $player.isMuted)
                }
                Section {
                    Label(player.isSpatial ? "Spatial video" : "2D video", systemImage: player.isSpatial ? "cube.transparent" : "rectangle")
                    if !player.formatDescription.isEmpty { Text(player.formatDescription).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text(player.isSpatial ? "Depth comes from the recorded views. A gentle strength usually gives the clearest result." : "This video has a single view, so Orbit plays it without depth.")
                }
            }.scrollContentBackground(.hidden).background(Color(white: 0.07))
                .navigationTitle("Playback").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .tint(OrbitTheme.ice)
        }
    }
}
