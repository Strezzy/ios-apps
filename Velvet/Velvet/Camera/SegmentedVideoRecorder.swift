import AVFoundation
import UniformTypeIdentifiers

/// AVAssetWriter's data-output initializer has no output URL. The delegate is
/// the only durable-write path, and it accepts only an authenticated vault writer.
final class SegmentedVideoRecorder: NSObject, AVAssetWriterDelegate {
    private let assetWriter = AVAssetWriter(contentType: .mpeg4Movie)
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let expectedWidth: Int
    private let expectedHeight: Int
    let vaultWriter: VaultVideoWriter
    private var startTime: CMTime?
    private var lastTime: CMTime?
    private let stateLock = NSLock()
    private var segmentError: Error?
    private var storedByteCount: Int64 = 0
    private var isCancelled = false
    var onFailure: (() -> Void)?

    init(vaultWriter: VaultVideoWriter, mode: VideoMode, audio: Bool, rotationAngle: CGFloat) throws {
        self.vaultWriter = vaultWriter
        expectedWidth = mode.width
        expectedHeight = mode.height
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: mode.outputSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = CGAffineTransform(rotationAngle: rotationAngle * .pi / 180)
        if audio {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ])
            audioInput?.expectsMediaDataInRealTime = true
        } else { audioInput = nil }
        super.init()
        assetWriter.outputFileTypeProfile = .mpeg4AppleHLS
        assetWriter.preferredOutputSegmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        assetWriter.delegate = self
        guard assetWriter.canApply(outputSettings: mode.outputSettings, forMediaType: .video),
              assetWriter.canAdd(videoInput) else { throw CameraError.unsupported }
        assetWriter.add(videoInput)
        if let audioInput {
            guard assetWriter.canAdd(audioInput) else { throw CameraError.unsupported }
            assetWriter.add(audioInput)
        }
        // Start writing on the first frame, once the initial segment time is known.
    }

    var byteCount: Int64 { stateLock.lock(); defer { stateLock.unlock() }; return storedByteCount }
    var duration: Double {
        guard let startTime, let lastTime else { return 0 }
        let seconds = CMTimeGetSeconds(lastTime - startTime)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    /// Called only on the capture queue. Frames are dropped on encoder backpressure
    /// instead of building an unbounded queue of private pixel buffers.
    func append(_ sample: CMSampleBuffer, isVideo: Bool) throws {
        stateLock.lock()
        let error = segmentError
        let cancelled = isCancelled
        stateLock.unlock()
        if let error { throw error }
        guard !cancelled, CMSampleBufferDataIsReady(sample) else { return }
        if isVideo {
            guard let buffer = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(buffer) == expectedWidth,
                  CVPixelBufferGetHeight(buffer) == expectedHeight else {
                // Old preview frames may be delivered while configuration settles.
                // Never silently upscale them into a mode advertised as higher quality.
                if startTime == nil { return }
                throw CameraError.unsupported
            }
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        if startTime == nil {
            guard isVideo else { return }
            assetWriter.initialSegmentStartTime = timestamp
            guard assetWriter.startWriting() else { throw CameraError.recordingFailed }
            assetWriter.startSession(atSourceTime: timestamp)
            startTime = timestamp
        }
        guard let startTime, timestamp >= startTime else { return }
        guard assetWriter.status == .writing else { throw CameraError.recordingFailed }
        let input = isVideo ? videoInput : audioInput
        if let input, input.isReadyForMoreMediaData {
            guard input.append(sample) else { throw CameraError.recordingFailed }
            if isVideo {
                let frameDuration = CMSampleBufferGetDuration(sample)
                lastTime = frameDuration.isValid && frameDuration.seconds.isFinite ? timestamp + frameDuration : timestamp
            }
        }
    }

    func finish(completion: @escaping (Result<Double, Error>) -> Void) {
        guard startTime != nil else { cancel(); completion(.failure(CameraError.noSamples)); return }
        guard assetWriter.status == .writing else { cancel(); completion(.failure(CameraError.recordingFailed)); return }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        let recordedDuration = duration
        assetWriter.finishWriting { [self] in
            stateLock.lock()
            let error = segmentError
            let cancelled = isCancelled
            stateLock.unlock()
            guard !cancelled, error == nil, assetWriter.status == .completed else {
                vaultWriter.cancel()
                completion(.failure(error ?? CameraError.recordingFailed))
                return
            }
            completion(.success(recordedDuration))
        }
    }

    func cancel() {
        stateLock.lock()
        isCancelled = true
        stateLock.unlock()
        if assetWriter.status == .writing { assetWriter.cancelWriting() }
        vaultWriter.cancel()
    }

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType) {
        // This callback may be on a framework thread. Serialize encrypted writes;
        // never dispatch the data onto an unbounded asynchronous work queue.
        stateLock.lock()
        guard !isCancelled, segmentError == nil else { stateLock.unlock(); return }
        do {
            try vaultWriter.append(segmentData, isInitialization: segmentType == .initialization)
            storedByteCount += Int64(segmentData.count)
            stateLock.unlock()
        } catch {
            segmentError = error
            stateLock.unlock()
            onFailure?()
        }
    }
}
