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
    private var activeVideoMode: VideoMode?
    private var selectedPhysicalLensID: String?
    private var focusObservation: NSKeyValueObservation?
    private var focusObservationID = UUID()
    private var subjectAreaObserver: NSObjectProtocol?
    private var activeFocusRequest: UUID?
    private var focusAdjustmentStarted = false
    private var configurationInFlight = false
    private var zoomTransitionID: UUID?
    var onError: ((Error) -> Void)?
    var onControlError: ((Error) -> Void)?
    var onProgress: ((Double, Int64) -> Void)?
    var onManualCapabilities: ((CameraManualCapabilities) -> Void)?
    var onFocusChange: ((UUID, CameraFocusState) -> Void)?

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    self?.abortRecording()
                    self?.releaseRecordingAudio()
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

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let subjectAreaObserver { NotificationCenter.default.removeObserver(subjectAreaObserver) }
    }

    func start(video: Bool, preferredMode: VideoMode?) async throws -> CameraCapabilities {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    desiredRunning = true
                    if cameraInput == nil { try configureInitialSession() }
                    let capabilities = try applyPreviewConfiguration(video: video, preferredMode: preferredMode, lensID: nil)
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else { throw CameraError.unavailable }
                    continuation.resume(returning: capabilities)
                } catch {
                    desiredRunning = false
                    if session.isRunning { session.stopRunning() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func configure(video: Bool, preferredMode: VideoMode?, lensID: String? = nil) async throws -> CameraCapabilities {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard desiredRunning, session.isRunning, !configurationInFlight, recorder == nil,
                          finishingRecorder == nil, photoDelegates.isEmpty else { throw CameraError.unavailable }
                    let capabilities = try applyPreviewConfiguration(video: video, preferredMode: preferredMode, lensID: lensID)
                    if let device = cameraInput?.device, device.isRampingVideoZoom {
                        configurationInFlight = true
                        let identifier = UUID()
                        zoomTransitionID = identifier
                        completeZoomTransition(identifier: identifier, device: device, capabilities: capabilities, remainingChecks: 60, continuation: continuation)
                    } else { continuation.resume(returning: capabilities) }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            desiredRunning = false
            configurationInFlight = false
            zoomTransitionID = nil
            resetFocusObservation()
            if let device = cameraInput?.device, (try? device.lockForConfiguration()) != nil {
                device.cancelVideoZoomRamp()
                device.unlockForConfiguration()
            }
            abortRecording()
            releaseRecordingAudio()
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
        selectedPhysicalLensID = device.uniqueID
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
            guard CameraConfigurationPolicy.isProcessedVideoSource(CMFormatDescriptionGetMediaSubType(format.formatDescription)) else { continue }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard [(1280, 720), (1920, 1080), (3840, 2160)].contains(where: { $0.0 == Int(dimensions.width) && $0.1 == Int(dimensions.height) }) else { continue }
            for fps in [24, 25, 30, 60, 100, 120] where format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(fps) && $0.maxFrameRate >= Double(fps) }) {
                for codec in CameraConfigurationPolicy.captureCodecs(width: Int(dimensions.width), height: Int(dimensions.height), fps: fps) {
                    let mode = VideoMode(width: Int(dimensions.width), height: Int(dimensions.height), fps: fps, codec: codec)
                    if verifier.canApply(outputSettings: mode.outputSettings, forMediaType: .video) { supported.insert(mode) }
                }
            }
        }
        return supported.sorted { ($0.height, $0.fps, $0.codec) < ($1.height, $1.fps, $1.codec) }
    }

    private func capabilities() throws -> CameraCapabilities {
        guard let device = cameraInput?.device else { throw CameraError.unavailable }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified)
        let wide = discovery.devices.first { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }
        let virtual = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera], mediaType: .video, position: .back).devices.first
        var nativeFactors: [String: Double] = [:]
        if let virtual {
            let factors = [1.0] + virtual.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
            if let wideIndex = virtual.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }), wideIndex < factors.count {
                for (index, constituent) in virtual.constituentDevices.enumerated() where index < factors.count {
                    nativeFactors[constituent.uniqueID] = factors[index] / factors[wideIndex]
                }
            }
        }
        var lenses: [CameraLens] = []
        for camera in discovery.devices {
            let native = lensNativeFactor(camera, wide: wide, knownFactors: nativeFactors)
            let isFront = camera.position == .front
            let label = isFront ? "Front" : CameraConfigurationPolicy.zoomLabel(nativeFactor: native)
            let lens = CameraLens(id: camera.uniqueID, label: label, isFront: isFront, nativeZoomFactor: native)
            lenses.append(lens)
        }
        lenses.sort { left, right in
            if left.isFront == right.isFront { return left.nativeZoomFactor < right.nativeZoomFactor }
            return !left.isFront
        }
        let dimensions = photoOutput.maxPhotoDimensions
        let megapixels = Double(dimensions.width) * Double(dimensions.height) / 1_000_000
        publishManualCapabilities()
        let selectedID = selectedPhysicalLensID ?? device.uniqueID
        let selectedDevice = AVCaptureDevice(uniqueID: selectedID) ?? device
        return CameraCapabilities(lenses: lenses, selectedLens: selectedID, modes: availableModes(device: selectedDevice),
            supportsRAW: !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty,
            supportsHEIF: photoOutput.availablePhotoCodecTypes.contains(.hevc),
            resolution: String(format: "Up to %.0f MP", megapixels),
            minimumExposureBias: device.minExposureTargetBias, maximumExposureBias: device.maxExposureTargetBias,
            currentExposureBias: device.exposureTargetBias,
            activeVideoMode: activeVideoMode)
    }

    private func lensNativeFactor(_ camera: AVCaptureDevice, wide: AVCaptureDevice?, knownFactors: [String: Double]) -> Double {
        if camera.position == .front || camera.deviceType == .builtInWideAngleCamera { return 1 }
        if camera.deviceType == .builtInUltraWideCamera { return 0.5 }
        if let factor = knownFactors[camera.uniqueID] { return factor }
        guard let wide else { return .nan }
        let wideFields: [Float] = wide.formats.map { $0.videoFieldOfView }
        let lensFields: [Float] = camera.formats.map { $0.videoFieldOfView }
        let wideFOV = Double(wideFields.max() ?? wide.activeFormat.videoFieldOfView)
        let lensFOV = Double(lensFields.max() ?? camera.activeFormat.videoFieldOfView)
        let wideHalfAngle = wideFOV * Double.pi / 360.0
        let lensHalfAngle = lensFOV * Double.pi / 360.0
        return tan(wideHalfAngle) / tan(lensHalfAngle)
    }

    func refreshManualCapabilities() { queue.async { [weak self] in self?.publishManualCapabilities() } }

    private func publishManualCapabilities() {
        guard let device = cameraInput?.device else { return }
        let format = device.activeFormat
        let minimum = format.minExposureDuration.seconds
        let maximum = min(format.maxExposureDuration.seconds, activeVideoMode.map { 1.0 / Double($0.fps) } ?? .infinity)
        let gains = device.deviceWhiteBalanceGains
        onManualCapabilities?(CameraManualCapabilities(
            exposureBias: device.exposureTargetBias,
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

    private func rearVirtualDevice(containing physical: AVCaptureDevice) -> AVCaptureDevice? {
        guard physical.position == .back else { return nil }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera], mediaType: .video, position: .back)
        return discovery.devices.first { $0.constituentDevices.contains(where: { $0.uniqueID == physical.uniqueID }) }
    }

    private func virtualZoomFactor(device: AVCaptureDevice, physicalID: String) -> CGFloat? {
        guard device.isVirtualDevice else { return nil }
        let factors = CameraConfigurationPolicy.nativeZoomFactors(
            constituentIDs: device.constituentDevices.map { $0.uniqueID },
            switchFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue })
        guard let factor = factors[physicalID] else { return nil }
        return CGFloat(factor)
    }

    /// Use the virtual camera only when it supports the exact physical lens's
    /// requested format. Otherwise a transactional physical-input switch keeps
    /// the selected resolution and frame rate truthful.
    private func captureDevice(for physical: AVCaptureDevice, mode: VideoMode?) -> AVCaptureDevice {
        guard let virtual = rearVirtualDevice(containing: physical),
              virtualZoomFactor(device: virtual, physicalID: physical.uniqueID) != nil else { return physical }
        if let mode, !availableModes(device: virtual).contains(mode) { return physical }
        return virtual
    }

    /// Transactional preview reconfiguration runs before the controller advertises
    /// the new mode. Recording never switches the camera back to a photo preset.
    private func applyPreviewConfiguration(video: Bool, preferredMode: VideoMode?, lensID: String?, allowVirtual: Bool = true) throws -> CameraCapabilities {
        guard let originalInput = cameraInput else { throw CameraError.unavailable }
        let physicalID = lensID ?? selectedPhysicalLensID ?? originalInput.device.uniqueID
        guard let physical = AVCaptureDevice(uniqueID: physicalID) else { throw CameraError.unsupported }
        let modes = availableModes(device: physical)
        let mode = video ? CameraConfigurationPolicy.videoMode(in: modes, retaining: preferredMode, isFront: physical.position == .front) : nil
        guard !video || mode != nil else { throw CameraError.unsupported }
        let device = allowVirtual ? captureDevice(for: physical, mode: mode) : physical
        let targetZoom = virtualZoomFactor(device: device, physicalID: physical.uniqueID) ?? device.minAvailableVideoZoomFactor
        let previousMode = activeVideoMode
        let previousLensID = selectedPhysicalLensID
        let previousZoom = originalInput.device.videoZoomFactor

        // No graph/preset change is needed for compatible rear-camera presets.
        // AVFoundation performs the optical handoff during this native zoom ramp.
        if session.isRunning, device.uniqueID == originalInput.device.uniqueID,
           mode == previousMode, physicalID != previousLensID {
            guard targetZoom >= device.minAvailableVideoZoomFactor,
                  targetZoom <= device.maxAvailableVideoZoomFactor else { throw CameraError.unsupported }
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            configureContinuousFocus(device, center: true)
            device.ramp(toVideoZoomFactor: targetZoom, withRate: 4)
            device.unlockForConfiguration()
            selectedPhysicalLensID = physicalID
            return try capabilities()
        }

        let replacement: AVCaptureDeviceInput
        if device.uniqueID == originalInput.device.uniqueID { replacement = originalInput }
        else { replacement = try AVCaptureDeviceInput(device: device) }
        session.beginConfiguration()
        do {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            if replacement !== originalInput {
                session.removeInput(originalInput)
                guard session.canAddInput(replacement) else { throw CameraError.unsupported }
                session.addInput(replacement)
                cameraInput = replacement
            }
            try applyFormat(mode, device: device, zoomFactor: targetZoom)
            // Some virtual devices cannot deliver Bayer RAW although their
            // physical cameras can. Preserve those still-photo controls by
            // falling back to the physical input instead of hiding RAW.
            if mode == nil, device.isVirtualDevice, photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
                throw CameraError.unsupported
            }
            activeVideoMode = mode
            selectedPhysicalLensID = physicalID
            session.commitConfiguration()
        } catch {
            let configurationError = error
            do {
                if cameraInput !== originalInput || !session.inputs.contains(originalInput) {
                    if let cameraInput, session.inputs.contains(cameraInput) { session.removeInput(cameraInput) }
                    guard session.canAddInput(originalInput) else { throw CameraError.configurationLost }
                    session.addInput(originalInput)
                    cameraInput = originalInput
                }
                try applyFormat(previousMode, device: originalInput.device, zoomFactor: previousZoom)
                activeVideoMode = previousMode
                selectedPhysicalLensID = previousLensID
            } catch {
                session.commitConfiguration()
                resetSessionAfterConfigurationFailure()
                throw CameraError.configurationLost
            }
            session.commitConfiguration()
            observeFocus(on: originalInput.device)
            if device.isVirtualDevice, allowVirtual {
                return try applyPreviewConfiguration(video: video, preferredMode: preferredMode, lensID: physicalID, allowVirtual: false)
            }
            throw configurationError
        }
        observeFocus(on: device)
        return try capabilities()
    }

    private func completeZoomTransition(identifier: UUID, device: AVCaptureDevice, capabilities: CameraCapabilities,
                                        remainingChecks: Int, continuation: CheckedContinuation<CameraCapabilities, Error>) {
        queue.asyncAfter(deadline: .now() + 0.05) { [self] in
            guard zoomTransitionID == identifier else { continuation.resume(throwing: CameraError.interrupted); return }
            guard desiredRunning, session.isRunning, cameraInput?.device.uniqueID == device.uniqueID else {
                configurationInFlight = false
                zoomTransitionID = nil
                continuation.resume(throwing: CameraError.interrupted)
                return
            }
            if device.isRampingVideoZoom, remainingChecks > 0 {
                completeZoomTransition(identifier: identifier, device: device, capabilities: capabilities,
                                       remainingChecks: remainingChecks - 1, continuation: continuation)
                return
            }
            if device.isRampingVideoZoom {
                // A stalled system ramp is ended under the device lock. Never
                // leave controls waiting indefinitely for a KVO notification.
                do {
                    try device.lockForConfiguration()
                    device.cancelVideoZoomRamp()
                    if let factor = virtualZoomFactor(device: device, physicalID: capabilities.selectedLens) {
                        device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, factor))
                    }
                    device.unlockForConfiguration()
                } catch {
                    configurationInFlight = false
                    zoomTransitionID = nil
                    resetSessionAfterConfigurationFailure()
                    continuation.resume(throwing: CameraError.configurationLost)
                    return
                }
            }
            configurationInFlight = false
            zoomTransitionID = nil
            continuation.resume(returning: capabilities)
        }
    }

    private func resetSessionAfterConfigurationFailure() {
        desiredRunning = false
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        resetFocusObservation()
        selectedPhysicalLensID = nil
        cameraInput = nil
        microphoneInput = nil
        activeVideoMode = nil
        session.commitConfiguration()
    }

    /// Caller owns beginConfiguration/commitConfiguration.
    private func applyFormat(_ mode: VideoMode?, device: AVCaptureDevice, zoomFactor: CGFloat) throws {
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if let mode {
            guard let format = device.formats.first(where: {
                let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return CameraConfigurationPolicy.isProcessedVideoSource(CMFormatDescriptionGetMediaSubType($0.formatDescription)) &&
                    Int(size.width) == mode.width && Int(size.height) == mode.height && $0.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= Double(mode.fps) && $0.maxFrameRate >= Double(mode.fps)
                }
            }) else { throw CameraError.unsupported }
            session.sessionPreset = .inputPriority
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.activeFormat = format
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(mode.fps))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(mode.fps))
                if format.isVideoHDRSupported { device.automaticallyAdjustsVideoHDREnabled = false; device.isVideoHDREnabled = false }
                guard zoomFactor >= device.minAvailableVideoZoomFactor, zoomFactor <= device.maxAvailableVideoZoomFactor else { throw CameraError.unsupported }
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = zoomFactor
                configureContinuousFocus(device, center: true, video: true)
            }
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            videoOutput.deliversPreviewSizedOutputBuffers = false
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                        kCVPixelBufferWidthKey as String: mode.width, kCVPixelBufferHeightKey as String: mode.height]
        } else {
            videoOutput.deliversPreviewSizedOutputBuffers = true
            guard session.canSetSessionPreset(.photo) else { throw CameraError.unsupported }
            session.sessionPreset = .photo
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                guard zoomFactor >= device.minAvailableVideoZoomFactor, zoomFactor <= device.maxAvailableVideoZoomFactor else { throw CameraError.unsupported }
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = zoomFactor
                configureContinuousFocus(device, center: true, video: false)
            }
        }
        configurePhotoQuality()
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = mode == nil ? .off : .standard }
        }
    }

    func capturePhoto(format: PhotoFormat, flash: CameraFlash, rotationAngle: CGFloat) async throws -> [CapturedPhoto] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CapturedPhoto], Error>) in
            queue.async { [self] in
                guard session.isRunning, !configurationInFlight, activeVideoMode == nil, recorder == nil, finishingRecorder == nil, photoDelegates.isEmpty else {
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
                    if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
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
                    guard session.isRunning, !configurationInFlight, recorder == nil, finishingRecorder == nil, photoDelegates.isEmpty,
                          activeVideoMode == mode else { throw CameraError.unsupported }
                    if withAudio {
                        session.beginConfiguration()
                        do { try configureAudio(); session.commitConfiguration() }
                        catch { session.commitConfiguration(); throw error }
                    }
                    let activeRecorder = try SegmentedVideoRecorder(vaultWriter: writer, mode: mode, audio: withAudio, rotationAngle: rotationAngle)
                    activeRecorder.onFailure = { [weak self, weak activeRecorder] in
                        self?.queue.async { [weak self, weak activeRecorder] in
                            guard let self, let activeRecorder,
                                  self.recorder === activeRecorder || self.finishingRecorder === activeRecorder else { return }
                            self.abortRecording()
                            self.releaseRecordingAudio()
                            self.onError?(CameraError.recordingFailed)
                        }
                    }
                    earliestRecordingTime = CMClockGetTime(CMClockGetHostTimeClock())
                    recorder = activeRecorder
                    recordingThumbnail = nil
                    recordingRotationAngle = rotationAngle
                    lastProgressTime = 0
                    continuation.resume()
                } catch { writer.cancel(); releaseRecordingAudio(); continuation.resume(throwing: error) }
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
                        releaseRecordingAudio()
                        continuation.resume(with: result.map { (current.vaultWriter, $0, thumbnail) })
                    }
                }
            }
        }
    }

    private func releaseRecordingAudio() {
        guard cameraInput != nil else { return }
        session.beginConfiguration()
        if let microphoneInput { session.removeInput(microphoneInput); self.microphoneInput = nil }
        if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
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

    /// Caller holds the device lock. Every configuration restores a supported
    /// continuous mode; a previous tap must never strand the lens in autoFocus.
    private func configureContinuousFocus(_ device: AVCaptureDevice, center: Bool, video: Bool? = nil) {
        activeFocusRequest = nil
        focusAdjustmentStarted = false
        if center, device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        else if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .none }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = video ?? (activeVideoMode != nil) }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func resetFocusObservation() {
        focusObservationID = UUID()
        focusObservation = nil
        if let subjectAreaObserver { NotificationCenter.default.removeObserver(subjectAreaObserver) }
        subjectAreaObserver = nil
        activeFocusRequest = nil
        focusAdjustmentStarted = false
    }

    private func observeFocus(on device: AVCaptureDevice) {
        resetFocusObservation()
        let observationID = focusObservationID
        focusObservation = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self, weak device] observed, _ in
            let adjusting = observed.isAdjustingFocus
            self?.queue.async { [weak self, weak device] in
                guard let self, let device, desiredRunning, focusObservationID == observationID, cameraInput?.device.uniqueID == device.uniqueID,
                      let request = activeFocusRequest else { return }
                if adjusting { focusAdjustmentStarted = true; onFocusChange?(request, .adjusting) }
                else if focusAdjustmentStarted { finishTapFocus(device: device, request: request) }
            }
        }
        subjectAreaObserver = NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device, queue: nil) { [weak self, weak device] _ in
                self?.queue.async { [weak self, weak device] in
                    guard let self, let device, desiredRunning, focusObservationID == observationID, cameraInput?.device.uniqueID == device.uniqueID else { return }
                    do {
                        try device.lockForConfiguration()
                        if let request = activeFocusRequest { onFocusChange?(request, .settled) }
                        configureContinuousFocus(device, center: true)
                        if device.exposureMode != .custom, device.isExposurePointOfInterestSupported {
                            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                        }
                        device.unlockForConfiguration()
                    } catch { onControlError?(CameraError.unsupported) }
                }
            }
    }

    func focus(at point: CGPoint, request: UUID) {
        queue.async { [self] in
            guard desiredRunning, session.isRunning, !configurationInFlight,
                  let point = CameraConfigurationPolicy.clampedFocusPoint(point), let device = cameraInput?.device else {
                onFocusChange?(request, .idle); return
            }
            do {
                try device.lockForConfiguration()
                activeFocusRequest = request
                focusAdjustmentStarted = false
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                else if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.exposureMode != .custom, device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
                onFocusChange?(request, .adjusting)
                // Fixed-focus lenses and taps on an already sharp subject may
                // not emit an adjusting->idle edge. Bound this wait as well.
                settleTapFocus(device: device, request: request, remainingChecks: 10)
            } catch { onFocusChange?(request, .idle); onControlError?(CameraError.unsupported) }
        }
    }

    private func settleTapFocus(device: AVCaptureDevice, request: UUID, remainingChecks: Int) {
        queue.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard desiredRunning, cameraInput?.device.uniqueID == device.uniqueID, activeFocusRequest == request else { return }
            if device.isAdjustingFocus, remainingChecks > 0 {
                settleTapFocus(device: device, request: request, remainingChecks: remainingChecks - 1)
            } else { finishTapFocus(device: device, request: request) }
        }
    }

    private func finishTapFocus(device: AVCaptureDevice, request: UUID) {
        guard activeFocusRequest == request else { return }
        do {
            try device.lockForConfiguration()
            configureContinuousFocus(device, center: false)
            device.unlockForConfiguration()
            onFocusChange?(request, .settled)
        } catch { activeFocusRequest = nil; onFocusChange?(request, .idle) }
    }

    func exposureBias(_ value: Float) {
        queue.async { [self] in
            guard desiredRunning, session.isRunning, !configurationInFlight, value.isFinite, let device = cameraInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, value))) { [weak self, weak device] _ in
                    self?.queue.async { [weak self, weak device] in
                        guard let self, let device, desiredRunning, cameraInput?.device.uniqueID == device.uniqueID else { return }
                        publishManualCapabilities()
                    }
                }
                device.unlockForConfiguration()
            } catch { onControlError?(CameraError.unsupported) }
        }
    }

    func manualExposure(iso: Float, shutterSeconds: Double) {
        configureDevice { device in
            guard device.isExposureModeSupported(.custom) else { throw CameraError.unsupported }
            let maximum = min(CMTimeGetSeconds(device.activeFormat.maxExposureDuration), self.activeVideoMode.map { 1.0 / Double($0.fps) } ?? .infinity)
            let duration = min(maximum, max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), shutterSeconds))
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
            self.configureContinuousFocus(device, center: true)
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
    }

    func zoom(_ factor: CGFloat) {
        configureDevice { device in
            guard factor.isFinite else { throw CameraError.unsupported }
            device.ramp(toVideoZoomFactor: min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, factor)), withRate: 4)
        }
    }

    private func configureDevice(_ operation: @escaping (AVCaptureDevice) throws -> Void) {
        queue.async { [self] in
            guard desiredRunning, session.isRunning, !configurationInFlight, let device = cameraInput?.device else { return }
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
            releaseRecordingAudio()
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
