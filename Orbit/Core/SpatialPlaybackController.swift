import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import UIKit
import VideoToolbox

/// A single synchronized presentation. The renderer owns only the most recent
/// frame; retaining an entire movie's decoded buffers would quickly exhaust RAM.
struct StereoVideoFrame {
    let left: CVPixelBuffer
    let right: CVPixelBuffer?
    let presentationTime: CMTime
    let transform: CGAffineTransform
    let isSpatial: Bool
}

/// AVPlayer remains the playback clock and audio owner. Spatial video is decoded
/// through Apple's tagged stereo output, rather than two independently timed
/// readers. Depth reconstruction is deliberately separate from media playback.
@MainActor
final class SpatialPlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isSpatial = false
    @Published private(set) var formatDescription = ""
    @Published private(set) var errorMessage: String?

    @Published var isMuted = false {
        didSet { player?.isMuted = isMuted }
    }
    @Published var isLooping = true
    @Published var depthStrength: Double = 0.65
    @Published var tiltEnabled = true
    @Published var fillScreen = false
    @Published var depthStatus = "Preparing depth…"

    private(set) var sourceSize: CGSize = .zero
    private(set) var displayTransform: CGAffineTransform = .identity

    private var player: AVPlayer?
    private var stereoOutput: AVPlayerVideoOutput?
    private var monoOutput: AVPlayerItemVideoOutput?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    private var scopedURL: URL?
    private var loadGeneration: UInt64 = 0
    private var seekGeneration: UInt64 = 0
    private var isSeeking = false
    private var wantsPlayback = false
    private var resumeAfterAudioInterruption = false
    private var lastFrameTime: CMTime?
    private var stereoWaitStarted: CFTimeInterval?
    private var receivedStereoPair = false
    private var nominalFrameRate: Float = 0
    private var rendererFailure: String?

    func load(url: URL) async {
        close()
        if let rendererFailure { fail(rendererFailure); return }
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        depthStatus = "Preparing depth…"

        guard url.isFileURL else {
            fail("Choose a video from Photos or Files to play it on your iPhone.")
            return
        }
        if url.startAccessingSecurityScopedResource() { scopedURL = url }

        do {
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            let (playable, assetDuration) = try await asset.load(.isPlayable, .duration)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            guard playable else { throw PlaybackError.unplayable }
            guard assetDuration.seconds.isFinite, assetDuration.seconds > 0 else {
                throw PlaybackError.invalidDuration
            }
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw PlaybackError.missingVideo
            }
            let (size, transform, frameRate) = try await videoTrack.load(
                .naturalSize, .preferredTransform, .nominalFrameRate
            )
            let stereoTracks = try await asset.loadTracks(withMediaCharacteristic: .containsStereoMultiviewVideo)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            let transformValues = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
            let displayBounds = CGRect(origin: .zero, size: size).applying(transform).standardized
            guard size.width.isFinite, size.height.isFinite, size.width != 0, size.height != 0,
                  transformValues.allSatisfy({ $0.isFinite }),
                  displayBounds.width.isFinite, displayBounds.height.isFinite,
                  displayBounds.width > 0, displayBounds.height > 0,
                  displayBounds.width < CGFloat(Int.max), displayBounds.height < CGFloat(Int.max),
                  abs(transform.a * transform.d - transform.b * transform.c) > 0.000001 else {
                throw PlaybackError.invalidGeometry
            }

            duration = assetDuration.seconds
            sourceSize = CGSize(width: abs(size.width), height: abs(size.height))
            displayTransform = transform
            nominalFrameRate = frameRate.isFinite && frameRate < Float(Int.max) ? frameRate : 0
            let spatialSource = !stereoTracks.isEmpty
            isSpatial = spatialSource && VTIsStereoMVHEVCDecodeSupported()
            let stereoUnavailable = spatialSource && !isSpatial
            depthStatus = stereoUnavailable ? "2D playback · stereo decoding unavailable" :
                (isSpatial ? "Preparing depth…" : "2D video · original playback")
            updateFormatDescription(fallback: stereoUnavailable)

            let item = AVPlayerItem(asset: asset)
            // Keep the system's streaming decoder bounded. We never load a
            // complete video or build a per-frame cache in application memory.
            item.preferredForwardBufferDuration = 2
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = isMuted
            newPlayer.allowsExternalPlayback = false
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            newPlayer.preventsDisplaySleepDuringVideoPlayback = true
            newPlayer.actionAtItemEnd = .pause
            player = newPlayer

            if isSpatial {
                let specification = AVVideoOutputSpecification(
                    tagCollections: [.stereoscopicForVideoOutput()]
                )
                specification.defaultOutputSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    AVVideoAllowWideColorKey: false
                ]
                let output = AVPlayerVideoOutput(specification: specification)
                stereoOutput = output
                newPlayer.videoOutput = output
            } else {
                attachMonoOutput(to: item)
            }

            observe(item: item, player: newPlayer, generation: generation)
            if UIApplication.shared.applicationState == .active { play() }
        } catch is CancellationError {
            guard generation == loadGeneration else { return }
            close()
        } catch {
            guard generation == loadGeneration else { return }
            fail(error.localizedDescription)
        }
    }

    func play() {
        guard let player, errorMessage == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            fail("The audio session could not start. Try opening the video again. \(error.localizedDescription)")
            return
        }
        wantsPlayback = true
        isPlaying = true
        if duration > 0, currentTime >= duration - 0.02 {
            seek(to: 0)
        } else if !isSeeking {
            player.play()
        }
    }

    func pause() {
        wantsPlayback = false
        resumeAfterAudioInterruption = false
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if wantsPlayback { pause() } else { play() }
    }

    func reportRenderingError(_ message: String) {
        rendererFailure = message
        fail(message)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0, let player, let item = player.currentItem else { return }
        let target = min(max(seconds, 0), duration)
        seekGeneration &+= 1
        let seek = seekGeneration
        let load = loadGeneration
        isSeeking = true
        currentTime = target
        lastFrameTime = nil
        stereoWaitStarted = nil
        item.cancelPendingSeeks()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 60_000),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == load, self.seekGeneration == seek else { return }
                self.isSeeking = false
                self.lastFrameTime = nil
                let actualTime = self.player?.currentTime().seconds ?? target
                self.currentTime = actualTime.isFinite ? min(max(actualTime, 0), self.duration) : target
                if finished, self.wantsPlayback { self.player?.play() }
                else if !self.wantsPlayback { self.player?.pause() }
            }
        }
    }

    /// Call with the display link's host timestamp. AVPlayer selects the video
    /// sample corresponding to its own audio clock. A nil result means the
    /// renderer should keep its last frame, including for tilt while paused.
    func frame(atHostTime hostTime: CFTimeInterval) -> StereoVideoFrame? {
        guard hostTime.isFinite, !isSeeking, let player,
              player.currentItem?.status == .readyToPlay else { return nil }

        return autoreleasepool {
            if let output = stereoOutput {
                let time = CMTime(seconds: hostTime, preferredTimescale: 1_000_000_000)
                if let sample = output.taggedBuffers(forHostTime: time) {
                    let left = sample.taggedBufferGroup.first {
                        $0.tags.contains(.stereoView(.leftEye))
                    }.flatMap { Self.pixelBuffer(from: $0) }
                    let right = sample.taggedBufferGroup.first {
                        $0.tags.contains(.stereoView(.rightEye))
                    }.flatMap { Self.pixelBuffer(from: $0) }

                    if let left, let right {
                        receivedStereoPair = true
                        stereoWaitStarted = nil
                        guard isNewPresentation(sample.presentationTime) else { return nil }
                        displayTransform = sample.activeConfiguration.preferredTransform
                        return StereoVideoFrame(left: left, right: right,
                                                presentationTime: sample.presentationTime,
                                                transform: displayTransform, isSpatial: true)
                    }
                    if receivedStereoPair { return nil }
                    // A one-eye sample can be shown flat while the decoder
                    // prepares the second view. It is never labelled 3D.
                    if let visible = left ?? right ?? sample.taggedBufferGroup.first.flatMap({ Self.pixelBuffer(from: $0) }) {
                        noteMissingStereo(at: hostTime)
                        guard isNewPresentation(sample.presentationTime) else { return nil }
                        return StereoVideoFrame(left: visible, right: nil,
                                                presentationTime: sample.presentationTime,
                                                transform: displayTransform, isSpatial: false)
                    }
                }
                noteMissingStereo(at: hostTime)
            }

            guard let output = monoOutput else { return nil }
            let itemTime = output.itemTime(forHostTime: hostTime)
            guard itemTime.isNumeric, output.hasNewPixelBuffer(forItemTime: itemTime) else { return nil }
            var presentationTime = CMTime.invalid
            guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime,
                                                           itemTimeForDisplay: &presentationTime) else { return nil }
            let time = presentationTime.isValid ? presentationTime : itemTime
            guard isNewPresentation(time) else { return nil }
            return StereoVideoFrame(left: pixelBuffer, right: nil, presentationTime: time,
                                    transform: displayTransform, isSpatial: false)
        }
    }

    /// Ends decoder, audio, and observers immediately. Safe to call repeatedly.
    func close() {
        loadGeneration &+= 1
        seekGeneration &+= 1
        wantsPlayback = false
        resumeAfterAudioInterruption = false
        player?.pause()
        player?.currentItem?.cancelPendingSeeks()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemStatusObservation?.invalidate()
        playerStatusObservation?.invalidate()
        itemStatusObservation = nil
        playerStatusObservation = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        player?.videoOutput = nil
        if let monoOutput { player?.currentItem?.remove(monoOutput) }
        player?.replaceCurrentItem(with: nil)
        player = nil
        stereoOutput = nil
        monoOutput = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        isPlaying = false
        isLoading = false
        isSeeking = false
        duration = 0
        currentTime = 0
        isSpatial = false
        sourceSize = .zero
        displayTransform = .identity
        formatDescription = ""
        errorMessage = nil
        lastFrameTime = nil
        stereoWaitStarted = nil
        receivedStereoPair = false
        nominalFrameRate = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func attachMonoOutput(to item: AVPlayerItem) {
        let output = AVPlayerItemVideoOutput(outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            AVVideoAllowWideColorKey: false
        ])
        output.suppressesPlayerRendering = true
        item.add(output)
        monoOutput = output
    }

    private func noteMissingStereo(at hostTime: CFTimeInterval) {
        // Once both eyes have decoded, temporary stalls should retain the last
        // frame rather than silently changing modes halfway through the movie.
        guard !receivedStereoPair, let item = player?.currentItem else { return }
        guard let started = stereoWaitStarted else {
            stereoWaitStarted = hostTime
            return
        }
        guard hostTime - started > 5 else { return }
        player?.videoOutput = nil
        stereoOutput = nil
        isSpatial = false
        lastFrameTime = nil
        depthStatus = "2D playback · stereo decoding unavailable"
        updateFormatDescription(fallback: true)
        attachMonoOutput(to: item)
    }

    private func isNewPresentation(_ time: CMTime) -> Bool {
        guard time.isNumeric else { return false }
        if let lastFrameTime, CMTimeCompare(time, lastFrameTime) == 0 { return false }
        lastFrameTime = time
        return true
    }

    private static func pixelBuffer(from tagged: CMTaggedBuffer) -> CVPixelBuffer? {
        switch tagged.buffer {
        case .pixelBuffer(let pixelBuffer): return pixelBuffer
        case .sampleBuffer(let sampleBuffer): return CMSampleBufferGetImageBuffer(sampleBuffer)
        @unknown default: return nil
        }
    }

    private func updateFormatDescription(fallback: Bool = false) {
        let displayed = CGRect(origin: .zero, size: sourceSize).applying(displayTransform).standardized.size
        let dimensions = "\(Int(displayed.width.rounded())) × \(Int(displayed.height.rounded()))"
        let fps = nominalFrameRate > 0 ? " · \(Int(nominalFrameRate.rounded())) fps" : ""
        let kind = fallback ? "Spatial source · 2D playback" : (isSpatial ? "Spatial video" : "2D video")
        formatDescription = "\(kind) · \(dimensions)\(fps)"
    }

    private func observe(item: AVPlayerItem, player: AVPlayer, generation: UInt64) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                switch status {
                case .readyToPlay: self.isLoading = false
                case .failed: self.fail(message ?? "This video could not be decoded on this iPhone.")
                case .unknown: break
                @unknown default: break
                }
            }
        }
        playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.isPlaying = self.wantsPlayback && status != .paused
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600),
                                                       queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation,
                      !self.isSeeking, time.seconds.isFinite else { return }
                self.currentTime = min(max(time.seconds, 0), self.duration)
            }
        }

        addNotification(.AVPlayerItemDidPlayToEndTime, object: item, generation: generation) { owner, _ in
            owner.currentTime = owner.duration
            if owner.isLooping && owner.wantsPlayback {
                owner.seek(to: 0)
            } else {
                owner.wantsPlayback = false
                owner.isPlaying = false
            }
        }
        addNotification(.AVPlayerItemFailedToPlayToEndTime, object: item, generation: generation) { owner, note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            owner.fail(error?.localizedDescription ?? "Playback stopped because this video could not be decoded.")
        }
        addNotification(UIApplication.willResignActiveNotification, generation: generation) { owner, _ in
            owner.pause()
        }
        addNotification(AVAudioSession.interruptionNotification, generation: generation) { owner, note in
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            if type == .began {
                let resume = owner.wantsPlayback
                owner.pause()
                owner.resumeAfterAudioInterruption = resume
            } else {
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                let resume = owner.resumeAfterAudioInterruption
                owner.resumeAfterAudioInterruption = false
                if resume && shouldResume && UIApplication.shared.applicationState == .active { owner.play() }
            }
        }
        addNotification(AVAudioSession.routeChangeNotification, generation: generation) { owner, note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return }
            if AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable { owner.pause() }
        }
    }

    private func addNotification(_ name: Notification.Name, object: Any? = nil, generation: UInt64,
                                 action: @escaping @MainActor (SpatialPlaybackController, Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                action(self, note)
            }
        }
        notificationTokens.append(token)
    }

    private func fail(_ message: String) {
        pause()
        isLoading = false
        errorMessage = message
    }

    deinit {
        // Observer closures capture this owner weakly. Still remove the periodic
        // observer and external resources if a caller omits explicit close().
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        scopedURL?.stopAccessingSecurityScopedResource()
    }
}

private enum PlaybackError: LocalizedError {
    case unplayable, missingVideo, invalidDuration, invalidGeometry

    var errorDescription: String? {
        switch self {
        case .unplayable: return "This file is not a playable video on this iPhone. Try importing the original MOV or MP4."
        case .missingVideo: return "This file does not contain a video track."
        case .invalidDuration: return "The video has no readable duration. Try importing the original file again."
        case .invalidGeometry: return "The video has invalid picture dimensions or orientation. Try importing the original file again."
        }
    }
}
