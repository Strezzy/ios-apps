import AVFoundation
import UIKit
import UniformTypeIdentifiers

/// All session/device/sample state belongs to one queue. No UI work or vault
/// catalogue mutation happens on this queue.
final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.velvet.capture", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var cameraInput: AVCaptureDeviceInput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var recorder: SegmentedVideoRecorder?
    private var finishingRecorder: SegmentedVideoRecorder?
    private var observers: [NSObjectProtocol] = []
    private var desiredRunning = false
    private var lastProgressTime: TimeInterval = 0
    private var recordingThumbnail: Data?
    private var finishingThumbnail: Data?
    private var recordingRotationAngle: CGFloat = 0
    private var earliestRecordingTime: CMTime?
    var onCapabilities: ((CameraCapabilities) -> Void)?
    var onError: ((Error) -> Void)?
    var onControlError: ((Error) -> Void)?
    var onProgress: ((Double, Int64) -> Void)?
    var onManualCapabilities: ((CameraManualCapabilities) -> Void)?

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.abortRecording()
                    self?.restorePhotoConfiguration()
                    self?.onError?(CameraError.interrupted)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.desiredRunning else { return }
                if !self.session.isRunning { self.session.startRunning() }
            }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    desiredRunning = true
                    if cameraInput == nil { try configureInitialSession() }
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else { throw CameraError.unavailable }
                    publishCapabilities()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            desiredRunning = false
            abortRecording()
            restorePhotoConfiguration()
            if session.isRunning { session.stopRunning() }
            photoDelegates.values.forEach { $0.cancel() }
            photoDelegates.removeAll()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configureInitialSession() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else { throw CameraError.unavailable }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .photo
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw CameraError.unavailable
        }
        session.addInput(input)
        cameraInput = input
        session.addOutput(photoOutput)
        session.addOutput(videoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        configurePhotoQuality()
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
    }

    private func configurePhotoQuality() {
        guard let device = cameraInput?.device else { return }
        photoOutput.maxPhotoQualityPrioritization = .quality
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
        if let maximum = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) { photoOutput.maxPhotoDimensions = maximum }
    }

    private func availableModes(device: AVCaptureDevice) -> [VideoMode] {
        var supported = Set<VideoMode>()
        let verifier = AVAssetWriter(contentType: .mpeg4Movie)
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard [(1280, 720), (1920, 1080), (3840, 2160)].contains(where: { $0.0 == Int(dimensions.width) && $0.1 == Int(dimensions.height) }) else { continue }
            for fps in [24, 25, 30, 60, 100, 120] where format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }) {
                // The high-rate/HDR/ProRes pipeline remains unavailable until it
                // has passed physical-device privacy, memory and thermal tests.
                guard fps <= 60 else { continue }
                for codec in ["h264", "hevc"] {
                    let mode = VideoMode(width: Int(dimensions.width), height: Int(dimensions.height), fps: fps, codec: codec)
                    if verifier.canApply(outputSettings: mode.outputSettings, forMediaType: .video) { supported.insert(mode) }
                }
            }
        }
        return supported.sorted { ($0.height, $0.fps, $0.codec) < ($1.height, $1.fps, $1.codec) }
    }

    private func publishCapabilities() {
        guard let device = cameraInput?.device else { return }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified)
        let lenses = discovery.devices.map { camera in
            let label: String
            if camera.position == .front { label = "Front" }
            else if camera.deviceType == .builtInUltraWideCamera { label = "Ultra wide" }
            else if camera.deviceType == .builtInTelephotoCamera { label = "Telephoto" }
            else { label = "Wide" }
            return CameraLens(id: camera.uniqueID, label: label, isFront: camera.position == .front)
        }
        let dimensions = photoOutput.maxPhotoDimensions
        let megapixels = Double(dimensions.width) * Double(dimensions.height) / 1_000_000
        onCapabilities?(CameraCapabilities(lenses: lenses, selectedLens: device.uniqueID, modes: availableModes(device: device),
            supportsRAW: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            supportsHEIF: photoOutput.availablePhotoCodecTypes.contains(.hevc),
            resolution: String(format: "Up to %.0f MP", megapixels),
            minimumExposureBias: device.minExposureTargetBias, maximumExposureBias: device.maxExposureTargetBias))
        publishManualCapabilities()
    }

    func refreshManualCapabilities() { queue.async { [weak self] in self?.publishManualCapabilities() } }

    private func publishManualCapabilities() {
        guard let device = cameraInput?.device else { return }
        let format = device.activeFormat
        let minimum = format.minExposureDuration.seconds
        let maximum = format.maxExposureDuration.seconds
        let gains = device.deviceWhiteBalanceGains
        onManualCapabilities?(CameraManualCapabilities(
            supportsExposure: device.isExposureModeSupported(.custom) && minimum.isFinite && maximum.isFinite && minimum > 0 && maximum > minimum && format.minISO > 0 && format.maxISO > format.minISO,
            minimumISO: format.minISO, maximumISO: format.maxISO,
            minimumShutterSeconds: minimum, maximumShutterSeconds: maximum,
            currentISO: device.iso, currentShutterSeconds: device.exposureDuration.seconds,
            exposureIsManual: device.exposureMode == .custom,
            supportsWhiteBalance: device.isWhiteBalanceModeSupported(.locked) && device.maxWhiteBalanceGain > 1,
            maximumWhiteBalanceGain: device.maxWhiteBalanceGain,
            redGain: gains.redGain, greenGain: gains.greenGain, blueGain: gains.blueGain,
            whiteBalanceIsLocked: device.whiteBalanceMode == .locked))
    }

    func selectLens(_ id: String) {
        queue.async { [self] in
            guard recorder == nil, finishingRecorder == nil, photoDelegates.isEmpty,
                  let oldInput = cameraInput, oldInput.device.uniqueID != id,
                  let device = AVCaptureDevice(uniqueID: id) else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.removeInput(oldInput)
                if session.canAddInput(newInput) { session.addInput(newInput); cameraInput = newInput }
                else { session.addInput(oldInput) }
                session.sessionPreset = .photo
                configurePhotoQuality()
                session.commitConfiguration()
                publishCapabilities()
            } catch { onError?(CameraError.unavailable) }
        }
    }

    func capturePhoto(format: PhotoFormat, flash: CameraFlash, rotationAngle: CGFloat) async throws -> [CapturedPhoto] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CapturedPhoto], Error>) in
            queue.async { [self] in
                guard session.isRunning, recorder == nil, finishingRecorder == nil, photoDelegates.isEmpty else {
                    continuation.resume(throwing: CameraError.unavailable); return
                }
                let settings: AVCapturePhotoSettings
                if format == .raw {
                    let rawTypes = photoOutput.availableRawPhotoPixelFormatTypes
                    guard let raw = rawTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) ?? rawTypes.first else {
                        continuation.resume(throwing: CameraError.unsupported); return
                    }
                    settings = AVCapturePhotoSettings(rawPixelFormatType: raw, processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                } else {
                    let codec: AVVideoCodecType = format == .heif ? .hevc : .jpeg
                    guard photoOutput.availablePhotoCodecTypes.contains(codec) else {
                        continuation.resume(throwing: CameraError.unsupported); return
                    }
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
                }
                settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
                settings.photoQualityPrioritization = .quality
                if photoOutput.supportedFlashModes.contains(flash.avMode) { settings.flashMode = flash.avMode }
                if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                let identifier = settings.uniqueID
                let delegate = PhotoCaptureDelegate(processedExtension: format == .heif ? "heic" : "jpg") { [weak self] result in
                    self?.queue.async { self?.photoDelegates.removeValue(forKey: identifier) }
                    continuation.resume(with: result)
                }
                photoDelegates[identifier] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    func startRecording(writer: VaultVideoWriter, mode: VideoMode, withAudio: Bool, rotationAngle: CGFloat) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard session.isRunning, recorder == nil, finishingRecorder == nil, photoDelegates.isEmpty,
                          let device = cameraInput?.device,
                          let format = device.formats.first(where: {
                              let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                              return Int(size.width) == mode.width && Int(size.height) == mode.height && $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(mode.fps) && $0.maxFrameRate >= Double(mode.fps) }
                          }) else { throw CameraError.unsupported }
                    session.beginConfiguration()
                    do {
                        session.sessionPreset = .inputPriority
                        try device.lockForConfiguration()
                        device.activeFormat = format
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(mode.fps))
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(mode.fps))
                        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                        if device.activeFormat.isVideoHDRSupported { device.automaticallyAdjustsVideoHDREnabled = false; device.isVideoHDREnabled = false }
                        device.unlockForConfiguration()
                        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
                            connection.videoRotationAngle = 0
                        }
                        videoOutput.deliversPreviewSizedOutputBuffers = false
                        videoOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            kCVPixelBufferWidthKey as String: mode.width,
                            kCVPixelBufferHeightKey as String: mode.height
                        ]
                        configurePhotoQuality()
                        if withAudio { try configureAudio() }
                        if let connection = videoOutput.connection(with: .video) {
                            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
                        }
                        session.commitConfiguration()
                    } catch { session.commitConfiguration(); throw error }
                    let activeRecorder = try SegmentedVideoRecorder(vaultWriter: writer, mode: mode, audio: withAudio, rotationAngle: rotationAngle)
                    activeRecorder.onFailure = { [weak self, weak activeRecorder] in
                        self?.queue.async { [weak self, weak activeRecorder] in
                            guard let self, let activeRecorder,
                                  self.recorder === activeRecorder || self.finishingRecorder === activeRecorder else { return }
                            self.abortRecording()
                            self.restorePhotoConfiguration()
                            self.onError?(CameraError.recordingFailed)
                        }
                    }
                    earliestRecordingTime = CMClockGetTime(CMClockGetHostTimeClock())
                    recorder = activeRecorder
                    recordingThumbnail = nil
                    recordingRotationAngle = rotationAngle
                    lastProgressTime = 0
                    continuation.resume()
                } catch { writer.cancel(); restorePhotoConfiguration(); continuation.resume(throwing: error) }
            }
        }
    }

    private func configureAudio() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try audioSession.setActive(true)
        if microphoneInput == nil {
            guard let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraError.unavailable }
            let input = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(input), session.canAddOutput(audioOutput) else { throw CameraError.unavailable }
            session.addInput(input)
            session.addOutput(audioOutput)
            microphoneInput = input
            audioOutput.setSampleBufferDelegate(self, queue: queue)
        }
    }

    func finishRecording() async throws -> (VaultVideoWriter, Double, Data?) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(VaultVideoWriter, Double, Data?), Error>) in
            queue.async { [self] in
                guard let current = recorder else { continuation.resume(throwing: CameraError.noSamples); return }
                recorder = nil
                finishingRecorder = current
                finishingThumbnail = recordingThumbnail
                recordingThumbnail = nil
                current.finish { [self] result in
                    queue.async { [self] in
                        guard finishingRecorder === current else {
                            continuation.resume(throwing: CameraError.interrupted)
                            return
                        }
                        let thumbnail = finishingThumbnail
                        finishingThumbnail = nil
                        finishingRecorder = nil
                        restorePhotoConfiguration()
                        continuation.resume(with: result.map { (current.vaultWriter, $0, thumbnail) })
                    }
                }
            }
        }
    }

    private func restorePhotoConfiguration() {
        guard cameraInput != nil else { return }
        session.beginConfiguration()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.deliversPreviewSizedOutputBuffers = true
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        if let microphoneInput { session.removeInput(microphoneInput); self.microphoneInput = nil }
        if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
        configurePhotoQuality()
        session.commitConfiguration()
        publishManualCapabilities()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func abortRecording() {
        recorder?.cancel()
        finishingRecorder?.cancel()
        recorder = nil
        finishingRecorder = nil
        recordingThumbnail = nil
        finishingThumbnail = nil
        earliestRecordingTime = nil
    }

    func focus(at point: CGPoint) {
        configureDevice { device in
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            }
        }
    }

    func exposureBias(_ value: Float) {
        configureDevice { device in device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, value)), completionHandler: nil) }
    }

    func manualExposure(iso: Float, shutterSeconds: Double) {
        configureDevice { device in
            guard device.isExposureModeSupported(.custom) else { throw CameraError.unsupported }
            let duration = min(CMTimeGetSeconds(device.activeFormat.maxExposureDuration), max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), shutterSeconds))
            device.setExposureModeCustom(duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000), iso: min(device.activeFormat.maxISO, max(device.activeFormat.minISO, iso)), completionHandler: nil)
        }
    }

    func whiteBalance(kelvin: Float) {
        configureDevice { device in
            guard device.isWhiteBalanceModeSupported(.locked) else { throw CameraError.unsupported }
            var gains = device.deviceWhiteBalanceGains(for: .init(temperature: kelvin, tint: 0))
            gains.redGain = min(device.maxWhiteBalanceGain, max(1, gains.redGain))
            gains.greenGain = min(device.maxWhiteBalanceGain, max(1, gains.greenGain))
            gains.blueGain = min(device.maxWhiteBalanceGain, max(1, gains.blueGain))
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
    }

    func whiteBalanceGains(red: Float, green: Float, blue: Float) {
        configureDevice { device in
            guard device.isWhiteBalanceModeSupported(.locked) else { throw CameraError.unsupported }
            let maximum = device.maxWhiteBalanceGain
            let gains = AVCaptureDevice.WhiteBalanceGains(redGain: min(maximum, max(1, red)),
                greenGain: min(maximum, max(1, green)), blueGain: min(maximum, max(1, blue)))
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
        }
    }

    func automaticExposure() {
        configureDevice { device in
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        }
    }

    func automaticWhiteBalance() {
        configureDevice { device in
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
    }

    func automaticControls() {
        configureDevice { device in
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
    }

    func zoom(_ factor: CGFloat) {
        configureDevice { device in device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, factor)) }
    }

    private func configureDevice(_ operation: @escaping (AVCaptureDevice) throws -> Void) {
        queue.async { [self] in
            guard let device = cameraInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                try operation(device)
                publishManualCapabilities()
            } catch { onControlError?(CameraError.unsupported) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let recorder else { return }
        if let earliestRecordingTime, CMSampleBufferGetPresentationTimeStamp(sampleBuffer) < earliestRecordingTime { return }
        do {
            let isVideo = output === videoOutput
            try recorder.append(sampleBuffer, isVideo: isVideo)
            if isVideo, recordingThumbnail == nil, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                // Small derived preview is encoded in memory and encrypted by VaultStore.
                let orientation: Int32
                switch recordingRotationAngle {
                case 90: orientation = 6
                case 180: orientation = 3
                case 270: orientation = 8
                default: orientation = 1
                }
                let image = CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: orientation)
                let factor = min(1, 420 / image.extent.width)
                let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                let context = CIContext(options: [.cacheIntermediates: false])
                if let cgImage = context.createCGImage(scaled, from: scaled.extent) { recordingThumbnail = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75) }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProgressTime > 0.2 {
                lastProgressTime = now
                onProgress?(recorder.duration, recorder.byteCount)
            }
        } catch {
            abortRecording()
            restorePhotoConfiguration()
            onError?(CameraError.recordingFailed)
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let processedExtension: String
    private let lock = NSLock()
    private var photos: [CapturedPhoto] = []
    private var error: Error?
    private var completion: ((Result<[CapturedPhoto], Error>) -> Void)?
    init(processedExtension: String, completion: @escaping (Result<[CapturedPhoto], Error>) -> Void) {
        self.processedExtension = processedExtension
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        guard completion != nil else { return }
        if let error { self.error = error; return }
        guard let data = photo.fileDataRepresentation() else { self.error = CameraError.unavailable; return }
        let dimensions = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
        photos.append(CapturedPhoto(data: data, fileExtension: photo.isRawPhoto ? "dng" : processedExtension, width: Int(dimensions.width), height: Int(dimensions.height)))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        lock.lock()
        let callback = completion
        completion = nil
        let result: Result<[CapturedPhoto], Error> = (error ?? self.error).map { .failure($0) } ?? (photos.isEmpty ? .failure(CameraError.unavailable) : .success(photos))
        photos.removeAll()
        lock.unlock()
        callback?(result)
    }

    func cancel() {
        lock.lock()
        let callback = completion
        completion = nil
        photos.removeAll()
        lock.unlock()
        callback?(.failure(CameraError.interrupted))
    }
}
