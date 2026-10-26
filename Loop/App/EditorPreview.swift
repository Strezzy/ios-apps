import SwiftUI
import QuartzCore
import CoreVideo
@preconcurrency import AVFoundation

/// Persistent native decoding plus a display-synchronized, bounded rendering queue.
/// Seeking finishes and presents one request before chasing the latest drag position.
@MainActor final class EditorPreview: ObservableObject {
    @Published var sourceFrame: CGImage?
    @Published var editingFrame: CGImage?
    @Published var renderedFrame: CGImage?
    @Published var time: Double = 0
    @Published var playing = false
    @Published var error: String?
    @Published private(set) var displayedTime: Double = 0
    private(set) var presentationCount = 0
    private(set) var nativeBufferCount = 0
    private(set) var fallbackFrameCount = 0
    private(set) var maximumNativeBufferSize = PixelSize(width: 0, height: 0)
    private(set) var isSuspendedForAnalysis = false
    var hasDecoderResources: Bool {
        player != nil || item != nil || output != nil || generator != nil || preparation != nil
    }
    var hasPendingRenderWork: Bool { renderer.isWorking || renderer.queuedCount > 0 }
    private var currentProject: LoopProject?
    private var currentURL: URL?
    private var session = UUID()
    private var preparation: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var generator: AVAssetImageGenerator?
    private var statusObservation: NSKeyValueObservation?
    private var playbackEndObservation: NSObjectProtocol?
    private var preferredTransform = CGAffineTransform.identity
    private var displayLink: CADisplayLink?
    private var displayTarget: PreviewDisplayTarget?
    private var ready = false
    private var scrubbing = false
    private var direction: Double = 1
    private var reverseFallback = false
    private var fallbackStartTime: Double = 0
    private var fallbackStartHost: CFTimeInterval = 0
    private var retainedSource: CGImage?
    private var retainedTime: Double = -.infinity
    private var latestSeek: SeekRequest?
    private var activeSeek: SeekRequest?
    private var awaitingSeekFrame = false
    private var seekFinishedAt: CFTimeInterval = 0
    private var seekEpoch = 0
    private var presentationMode: PreviewPresentationMode = .result

    private struct SeekRequest {
        var id = UUID()
        var time: Double
        var exact: Bool
        var resume: Bool
    }

    private lazy var renderer = LatestPreviewWork<PreviewRenderRequest, PreviewRenderedFrames>(
        operation: { request in
            try await Task.detached(priority: .userInitiated) {
                try PreviewRenderedFrames.render(request)
            }.value
        },
        didProduce: { [weak self] frames in self?.present(frames) },
        didFail: { [weak self] error in self?.error = error.localizedDescription }
    )

    func refresh(project: LoopProject, url: URL) {
        let previous = currentProject
        let changed = previous != project
        configure(project: project, url: url)
        guard currentURL == url, !isSuspendedForAnalysis else { return }
        if playing {
            // Playhead notifications must not trigger duplicate renders or seeks.
            guard changed else { return }
            updateCadence()
            if previous?.export.playback != project.export.playback || previous?.export.speed != project.export.speed {
                direction = project.export.playback == .reverse ? -1 : 1
                reverseFallback = false
                requestSeek(playbackStart(at: time), exact: true, resume: true)
            } else if time < project.trimStart || time >= project.trimEnd {
                requestSeek(playbackStart(at: time), exact: true, resume: true)
            } else if let source = retainedSource {
                enqueue(.image(source), at: retainedTime)
            }
            return
        }
        let target = clamp(time)
        if let source = retainedSource, abs(target - retainedTime) <= 1.0 / 60_000 {
            if changed { enqueue(.image(source), at: target) }
        } else {
            requestSeek(target, exact: !scrubbing, resume: false)
        }
    }

    func beginScrubbing() {
        guard !isSuspendedForAnalysis else { return }
        stop()
        scrubbing = true
        updateCadence()
    }

    func setPresentationMode(_ mode: PreviewPresentationMode) {
        guard mode != presentationMode else { return }
        presentationMode = mode
        if let source = retainedSource { enqueue(.image(source), at: retainedTime) }
    }

    /// Placement must use the pixels currently visible, rather than a newer slider
    /// target that the decoder has not reached. Old seek/render results are invalidated.
    func beginCanvasInteraction() {
        stop()
        // There is nothing to pin until the first picture arrives. Let its initial
        // seek complete instead of leaving an empty canvas with no work scheduled.
        guard let source = retainedSource else { return }
        scrubbing = false
        seekEpoch += 1
        item?.cancelPendingSeeks()
        fallbackTask?.cancel(); fallbackTask = nil
        generator?.cancelAllCGImageGeneration()
        activeSeek = nil; latestSeek = nil; awaitingSeekFrame = false
        renderer.invalidate()
        time = retainedTime
        enqueue(.image(source), at: retainedTime)
        updateDisplayLinkState()
    }

    func seek(to requestedTime: Double, project: LoopProject, url: URL) {
        stop()
        configure(project: project, url: url)
        time = clamp(requestedTime)
        requestSeek(time, exact: !scrubbing, resume: false)
    }

    func endScrubbing(project: LoopProject, url: URL) {
        scrubbing = false
        configure(project: project, url: url)
        requestSeek(clamp(time), exact: true, resume: false)
    }

    func toggle(project: LoopProject, url: URL) {
        guard !isSuspendedForAnalysis else { return }
        if playing { stop(); refresh(project: project, url: url); return }
        configure(project: project, url: url)
        scrubbing = false
        direction = project.export.playback == .reverse ? -1 : 1
        reverseFallback = false
        playing = true
        updateCadence()
        requestSeek(playbackStart(at: time), exact: true, resume: true)
        updateDisplayLinkState()
    }

    func stop() {
        playing = false
        reverseFallback = false
        player?.pause()
        updateDisplayLinkState()
    }

    /// Keep the bounded visible raster while releasing the paused player's decoder,
    /// pixel-buffer output and fallback generator. A paused 4K player still owns those
    /// resources, so stopping playback alone is insufficient before Vision analysis.
    func suspendForAnalysis() async {
        if isSuspendedForAnalysis {
            await renderer.waitUntilIdle()
            return
        }
        isSuspendedForAnalysis = true
        playing = false
        scrubbing = false
        if retainedSource != nil { time = retainedTime }
        let preparing = preparation
        let generatingFallback = fallbackTask
        releaseDecoder()
        // Cancellation is asynchronous. Wait for captured tasks to relinquish their
        // own strong generator/asset references before starting the analysis decoder.
        await preparing?.value
        await generatingFallback?.value
        await renderer.waitUntilIdle()
        if isSuspendedForAnalysis { FrameRenderer.clearCaches() }
    }

    /// A cleared/disappeared editor must not be resurrected by an old tracking task.
    /// Resuming stays paused and renders the saved result before native seeking resumes.
    func resumeAfterAnalysis(project: LoopProject, url: URL) {
        guard isSuspendedForAnalysis else { return }
        isSuspendedForAnalysis = false
        configure(project: project, url: url)
        if let source = retainedSource { enqueue(.image(source), at: retainedTime) }
        requestSeek(clamp(time), exact: true, resume: false)
    }

    func clear() {
        playing = false
        scrubbing = false
        isSuspendedForAnalysis = false
        releaseDecoder()
        currentURL = nil; currentProject = nil
        retainedSource = nil; retainedTime = -.infinity
        sourceFrame = nil; editingFrame = nil; renderedFrame = nil
        error = nil
    }

    private func releaseDecoder() {
        session = UUID()
        seekEpoch += 1
        preparation?.cancel(); preparation = nil
        fallbackTask?.cancel(); fallbackTask = nil
        generator?.cancelAllCGImageGeneration(); generator = nil
        item?.cancelPendingSeeks()
        player?.pause()
        if let output { item?.remove(output) }
        player?.replaceCurrentItem(with: nil)
        statusObservation?.invalidate(); statusObservation = nil
        if let observation = playbackEndObservation { NotificationCenter.default.removeObserver(observation) }
        playbackEndObservation = nil
        displayLink?.invalidate(); displayLink = nil; displayTarget = nil
        player = nil; item = nil; output = nil
        ready = false
        reverseFallback = false
        activeSeek = nil; latestSeek = nil; awaitingSeekFrame = false
        renderer.invalidate()
    }

    private func configure(project: LoopProject, url: URL) {
        if currentURL == url {
            let changedRange = currentProject?.trimStart != project.trimStart || currentProject?.trimEnd != project.trimEnd
            currentProject = project
            // Trim edits normally happen while paused. Keeping the old native bounds
            // can strand playback at the original out point even after the UI moves on.
            if changedRange { updatePlaybackBounds() }
        } else {
            // Never open a second decoder while analysis owns the media resources.
            if isSuspendedForAnalysis {
                currentURL = url; currentProject = project
                return
            }
            clear()
            currentURL = url
            currentProject = project
        }
        guard !isSuspendedForAnalysis, player == nil, preparation == nil else { return }
        let token = session
        let target = PreviewDisplayTarget(owner: self)
        displayTarget = target
        let link = CADisplayLink(target: target, selector: #selector(PreviewDisplayTarget.tick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
        updateCadence()
        preparation = Task { [weak self] in
            defer { if self?.session == token { self?.preparation = nil } }
            do {
                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw LoopError.invalidVideo("This video has no readable picture track.")
                }
                let (transform, naturalSize) = try await track.load(.preferredTransform, .naturalSize)
                guard naturalSize.width.isFinite, naturalSize.height.isFinite,
                      naturalSize.width > 0, naturalSize.height > 0 else {
                    throw LoopError.invalidVideo("This video has invalid preview dimensions.")
                }
                try Task.checkCancellation()
                guard let self, self.session == token else { return }
                self.preferredTransform = transform
                let item = AVPlayerItem(asset: asset)
                let colorProperties: [String: String] = [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ]
                // Request bounded native output buffers. Scaling only after copyPixelBuffer
                // would still retain full 4K BGRA buffers in the running/pending render queue.
                let rawEdge = max(1, max(abs(naturalSize.width), abs(naturalSize.height)))
                let previewScale = min(1, 960 / rawEdge)
                let outputWidth = max(1, Int((abs(naturalSize.width) * previewScale).rounded()))
                let outputHeight = max(1, Int((abs(naturalSize.height) * previewScale).rounded()))
                // Native pixel transfer tone-maps HDR into the same SDR preview space.
                let output = AVPlayerItemVideoOutput(outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: outputWidth,
                    kCVPixelBufferHeightKey as String: outputHeight,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    AVVideoAllowWideColorKey: false,
                    AVVideoColorPropertiesKey: colorProperties
                ])
                output.suppressesPlayerRendering = true
                item.add(output)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                player.allowsExternalPlayback = false
                player.automaticallyWaitsToMinimizeStalling = false
                player.actionAtItemEnd = .none
                self.item = item; self.output = output; self.player = player
                self.generator = MediaEngine.makeGenerator(url: url, maximumDimension: 960)
                self.updatePlaybackBounds()
                self.statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor in self?.itemStatusChanged(session: token) }
                }
                self.playbackEndObservation = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.itemReachedEnd(session: token) }
                }
            } catch is CancellationError { }
            catch {
                guard let self, self.session == token else { return }
                self.error = error.localizedDescription
                self.playing = false
                self.updateDisplayLinkState()
            }
        }
    }

    private func itemStatusChanged(session token: UUID) {
        guard token == session, let item else { return }
        switch item.status {
        case .readyToPlay:
            ready = true
            if latestSeek == nil && activeSeek == nil {
                latestSeek = SeekRequest(time: clamp(time), exact: true, resume: playing)
            }
            performNextSeek()
        case .failed:
            error = item.error?.localizedDescription ?? "This video could not be previewed."
            stop()
        default: break
        }
    }

    private func requestSeek(_ target: Double, exact: Bool, resume: Bool) {
        guard !isSuspendedForAnalysis else { return }
        let clamped = clamp(target)
        if let active = activeSeek, abs(active.time - clamped) < 1.0 / 60_000,
           (!exact || active.exact), !resume { return }
        latestSeek = SeekRequest(time: clamped, exact: exact,
                                  resume: resume || (playing && (activeSeek?.resume == true || latestSeek?.resume == true)))
        performNextSeek()
        updateDisplayLinkState()
    }

    private func performNextSeek() {
        guard ready, activeSeek == nil, let next = latestSeek, let player else { return }
        latestSeek = nil
        activeSeek = next
        awaitingSeekFrame = false
        player.pause()
        let tolerance = next.exact ? CMTime.zero : CMTime(seconds:
            0.5 / max(1, currentProject?.metadata.nominalFrameRate ?? 30), preferredTimescale: 60_000)
        let token = session
        let epoch = seekEpoch
        player.seek(to: CMTime(seconds: next.time, preferredTimescale: 60_000),
                    toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.session == token, self.seekEpoch == epoch,
                      self.activeSeek?.id == next.id else { return }
                if !finished {
                    self.activeSeek = nil
                    // Changing a playback boundary may interrupt AVFoundation's seek.
                    // Preserve the latest play intent instead of leaving a paused player
                    // behind a Pause button with no remaining work scheduled.
                    if self.latestSeek == nil, self.playing, self.item?.status != .failed {
                        self.latestSeek = SeekRequest(time: self.playbackStart(at: self.time), exact: true, resume: true)
                    }
                    self.performNextSeek()
                    self.updateDisplayLinkState()
                    return
                }
                self.awaitingSeekFrame = true
                self.seekFinishedAt = CACurrentMediaTime()
                self.pullSeekFrame()
                self.updateDisplayLinkState()
            }
        }
    }

    private func pullSeekFrame() {
        guard awaitingSeekFrame, let active = activeSeek, let output else { return }
        var actual = CMTime.invalid
        // A paused seek may provide a buffer even when hasNewPixelBuffer is false.
        if let buffer = output.copyPixelBuffer(forItemTime: CMTime(seconds: active.time, preferredTimescale: 60_000),
                                                itemTimeForDisplay: &actual) {
            recordNativeBuffer(buffer)
            finishSeekFrame(.buffer(buffer, preferredTransform), request: active)
        } else if CACurrentMediaTime() - seekFinishedAt > 0.25, fallbackTask == nil, let generator {
            // Some codecs cannot vend a paused player frame. This persistent exact
            // generator is a fallback, never cancelled by continued pointer movement.
            let token = session
            let epoch = seekEpoch
            fallbackTask = Task { [weak self] in
                defer { if self?.session == token && self?.seekEpoch == epoch { self?.fallbackTask = nil } }
                do {
                    let image = try await generator.image(at: CMTime(seconds: active.time, preferredTimescale: 60_000)).image
                    guard let self, self.session == token, !Task.isCancelled,
                          self.activeSeek?.id == active.id, self.awaitingSeekFrame else { return }
                    self.fallbackFrameCount += 1
                    self.finishSeekFrame(.image(image), request: active)
                } catch is CancellationError { }
                catch {
                    guard let self, self.session == token, self.activeSeek?.id == active.id else { return }
                    self.error = error.localizedDescription
                    self.activeSeek = nil; self.awaitingSeekFrame = false
                    self.performNextSeek()
                }
            }
        }
    }

    private func finishSeekFrame(_ source: PreviewSource, request: SeekRequest) {
        enqueue(source, at: request.time)
        awaitingSeekFrame = false
        activeSeek = nil
        if latestSeek != nil { performNextSeek() }
        else if playing && request.resume { startNativePlayback() }
        updateDisplayLinkState()
    }

    private func startNativePlayback() {
        guard playing, let project = currentProject, let item, let player else { return }
        if direction < 0 && !item.canPlayReverse {
            reverseFallback = true
            fallbackStartTime = player.currentTime().seconds
            fallbackStartHost = CACurrentMediaTime()
            player.pause()
        } else {
            reverseFallback = false
            player.playImmediately(atRate: Float(project.export.speed * direction))
        }
    }

    fileprivate func displayTick(_ link: CADisplayLink) {
        if awaitingSeekFrame { pullSeekFrame() }
        guard playing, activeSeek == nil, let project = currentProject, let player, let output else { return }
        let hostTime = link.targetTimestamp > 0 ? link.targetTimestamp : link.timestamp + link.duration
        if reverseFallback {
            let target = fallbackStartTime - (hostTime - fallbackStartHost) * project.export.speed
            if target <= project.trimStart { reachedBoundary() }
            else { requestSeek(target, exact: false, resume: false) }
            return
        }
        let itemTime = output.itemTime(forHostTime: hostTime)
        let seconds = itemTime.seconds.isFinite ? itemTime.seconds : player.currentTime().seconds
        guard seconds.isFinite else { return }
        let current = player.currentTime().seconds
        if hasReachedBoundary(at: seconds) || (current.isFinite && hasReachedBoundary(at: current)) {
            reachedBoundary()
            return
        }
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
        var actual = CMTime.invalid
        guard let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &actual) else { return }
        recordNativeBuffer(buffer)
        let sourceTime = actual.seconds.isFinite ? actual.seconds : seconds
        enqueue(.buffer(buffer, preferredTransform), at: clamp(sourceTime))
    }

    private func reachedBoundary() {
        guard playing, activeSeek == nil, let project = currentProject else { return }
        if project.export.playback == .bounce { direction *= -1 }
        requestSeek(direction < 0 ? clamp(project.trimEnd) : project.trimStart + CreativeMotion.seamDuration(project), exact: true, resume: true)
    }

    private func itemReachedEnd(session token: UUID) {
        guard session == token, playing, activeSeek == nil, latestSeek == nil,
              let player, let project = currentProject else { return }
        // Some decoders stop producing buffers on the final sample before a display
        // tick sees the exact out point. Use the native end notification as well.
        // Checking the current side of the range rejects a delayed notification from
        // the preceding loop or direction after its seek has already completed.
        let current = player.currentTime().seconds
        let tolerance = min(project.duration / 2, 1 / max(1, project.metadata.nominalFrameRate))
        if current.isFinite && hasReachedBoundary(at: current, tolerance: tolerance) { reachedBoundary() }
    }

    private func hasReachedBoundary(at value: Double, tolerance: Double = 1.0 / 60_000) -> Bool {
        guard let project = currentProject else { return false }
        return direction > 0 ? value >= project.trimEnd - tolerance : value <= project.trimStart + tolerance
    }

    private func playbackStart(at requestedTime: Double) -> Double {
        guard let project = currentProject else { return clamp(requestedTime) }
        // The end thumb can select a time inside the final video sample. Replaying
        // that sample has no visible motion; Play there starts the selected loop.
        let finalSample = project.trimEnd - min(project.duration / 2,
            1 / max(1, project.metadata.nominalFrameRate))
        if direction > 0 && (requestedTime >= finalSample || requestedTime < project.trimStart + CreativeMotion.seamDuration(project)) { return project.trimStart + CreativeMotion.seamDuration(project) }
        if direction < 0 && requestedTime <= project.trimStart + 1.0 / 60_000 { return clamp(project.trimEnd) }
        return clamp(requestedTime)
    }

    private func recordNativeBuffer(_ buffer: CVPixelBuffer) {
        nativeBufferCount += 1
        let size = PixelSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if size.longEdge > maximumNativeBufferSize.longEdge { maximumNativeBufferSize = size }
    }

    private func enqueue(_ source: PreviewSource, at sourceTime: Double) {
        guard !isSuspendedForAnalysis, let project = currentProject else { return }
        renderer.submit(PreviewRenderRequest(source: source, project: project, sourceTime: sourceTime,
                                             session: session, presentation: presentationMode))
    }

    private func present(_ frames: PreviewRenderedFrames) {
        guard frames.session == session, !isSuspendedForAnalysis else { return }
        retainedSource = frames.source
        retainedTime = frames.sourceTime
        sourceFrame = frames.source
        if let editing = frames.editing { editingFrame = editing }
        if let result = frames.result { renderedFrame = result }
        displayedTime = frames.sourceTime
        presentationCount += 1
        error = nil
        if playing && !scrubbing { time = frames.sourceTime }
    }

    private func clamp(_ value: Double) -> Double {
        guard let project = currentProject else { return max(0, value.isFinite ? value : 0) }
        return min(max(project.trimStart, project.trimEnd - 1.0 / 60_000),
                   max(project.trimStart, value.isFinite ? value : project.trimStart))
    }

    private func updatePlaybackBounds() {
        guard let project = currentProject else { return }
        item?.forwardPlaybackEndTime = CMTime(seconds: project.trimEnd, preferredTimescale: 60_000)
        item?.reversePlaybackEndTime = CMTime(seconds: project.trimStart, preferredTimescale: 60_000)
    }

    private func updateCadence() {
        guard let project = currentProject else { return }
        let maximum = UIScreen.main.maximumFramesPerSecond
        let rate = PreviewCadence.preferredRate(sourceRate: project.metadata.nominalFrameRate,
                                                speed: playing ? project.export.speed : 1,
                                                displayMaximum: maximum)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, rate),
                                                               maximum: Float(maximum), preferred: rate)
    }

    private func updateDisplayLinkState() {
        displayLink?.isPaused = !(playing || activeSeek != nil || latestSeek != nil || awaitingSeekFrame)
    }
}

@MainActor private final class PreviewDisplayTarget: NSObject {
    weak var owner: EditorPreview?
    init(owner: EditorPreview) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        guard let owner else { link.invalidate(); return }
        owner.displayTick(link)
    }
}
