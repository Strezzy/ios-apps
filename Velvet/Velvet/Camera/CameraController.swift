import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var isVideoMode = false
    @Published private(set) var isFrontCamera = false
    @Published private(set) var controlRotationDegrees: Double = 0
    @Published var errorMessage: String?
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var selectedLensID = ""
    @Published private(set) var videoModes: [VideoMode] = []
    @Published private(set) var selectedVideoMode = VideoMode.standard
    @Published var photoFormat: PhotoFormat = .heif
    @Published var flashMode: CameraFlash = .off
    @Published private(set) var supportsRAW = false
    @Published private(set) var supportsHEIF = true
    @Published private(set) var photoResolutionLabel = "Original quality"
    @Published private(set) var recordingSeconds: Double = 0
    @Published private(set) var recordingBytes: Int64 = 0
    @Published var microphoneEnabled = true
    @Published private(set) var lastCaptureID: UUID?
    @Published private(set) var minimumExposureBias: Float = -2
    @Published private(set) var maximumExposureBias: Float = 2
    @Published var exposureBias: Float = 0
    @Published private(set) var manualCapabilities: CameraManualCapabilities?
    var session: AVCaptureSession { engine.session }
    private(set) var captureRotationAngle: CGFloat = 90
    var rearZoomLenses: [CameraLens] { availableLenses.filter { !$0.isFront } }
    var canFlipCamera: Bool { availableLenses.contains(where: { $0.isFront }) && !rearZoomLenses.isEmpty }
    private var videoPreferences: [Bool: VideoMode] = [:]
    private var lastRearLensID: String?
    private var orientationObserver: NSObjectProtocol?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var observingOrientation = false
    private let engine = CaptureEngine()
    private let vault: VaultStore
    private var generation = UUID()
    private var isStarting = false

    init(vault: VaultStore) {
        self.vault = vault
        engine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = error.localizedDescription
                self?.isRecording = false
                self?.isCapturing = false
            }
        }
        engine.onControlError = { [weak self] error in
            Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
        }
        engine.onProgress = { [weak self] seconds, bytes in
            Task { @MainActor [weak self] in
                guard self?.isRecording == true else { return }
                self?.recordingSeconds = seconds
                self?.recordingBytes = bytes
            }
        }
        engine.onManualCapabilities = { [weak self] capabilities in
            Task { @MainActor [weak self] in self?.manualCapabilities = capabilities }
        }
    }

    func start() async {
        guard vault.isUnlocked, !isReady, !isStarting else { return }
        isStarting = true
        isConfiguring = true
        let requestGeneration = generation
        defer {
            if generation == requestGeneration { isStarting = false; isConfiguring = false }
        }
        let authorized = await Self.authorize(.video)
        guard generation == requestGeneration, vault.isUnlocked else { return }
        guard authorized else { errorMessage = CameraError.permission.localizedDescription; return }
        do {
            let capabilities = try await engine.start(video: isVideoMode, preferredMode: videoPreferences[isFrontCamera])
            guard generation == requestGeneration, vault.isUnlocked else { return }
            apply(capabilities)
            beginOrientationTracking()
            isReady = true
            errorMessage = nil
        } catch {
            if generation == requestGeneration { errorMessage = error.localizedDescription }
        }
    }

    private func apply(_ capabilities: CameraCapabilities) {
        availableLenses = capabilities.lenses
        selectedLensID = capabilities.selectedLens
        isFrontCamera = availableLenses.first { $0.id == selectedLensID }?.isFront ?? false
        if !isFrontCamera { lastRearLensID = selectedLensID }
        videoModes = capabilities.modes
        if let applied = capabilities.activeVideoMode {
            isVideoMode = true
            selectedVideoMode = applied
            videoPreferences[isFrontCamera] = applied
        } else {
            isVideoMode = false
            selectedVideoMode = CameraConfigurationPolicy.videoMode(in: videoModes,
                retaining: videoPreferences[isFrontCamera], isFront: isFrontCamera) ?? .standard
        }
        supportsRAW = capabilities.supportsRAW
        supportsHEIF = capabilities.supportsHEIF
        photoResolutionLabel = capabilities.resolution
        minimumExposureBias = capabilities.minimumExposureBias
        maximumExposureBias = capabilities.maximumExposureBias
        if !isVideoMode {
            if photoFormat == .raw && !supportsRAW { photoFormat = supportsHEIF ? .heif : .jpeg }
            if photoFormat == .heif && !supportsHEIF { photoFormat = .jpeg }
        }
        configureRotationCoordinator()
    }

    func setCaptureMode(video: Bool) {
        guard video != isVideoMode else { return }
        requestConfiguration(video: video, mode: video ? selectedVideoMode : nil)
    }

    func selectVideoMode(_ mode: VideoMode) {
        guard videoModes.contains(mode), mode != selectedVideoMode else { return }
        if isVideoMode { requestConfiguration(video: true, mode: mode) }
        else if !isConfiguring, !isRecording, !isCapturing {
            selectedVideoMode = mode
            videoPreferences[isFrontCamera] = mode
        }
    }

    private func requestConfiguration(video: Bool, mode: VideoMode?, lensID: String? = nil) {
        guard vault.isUnlocked, isReady, !isConfiguring, !isRecording, !isCapturing else { return }
        isConfiguring = true
        let expected = generation
        Task {
            defer { if generation == expected { isConfiguring = false } }
            do {
                let capabilities = try await engine.configure(video: video, preferredMode: mode, lensID: lensID)
                guard expected == generation, vault.isUnlocked else { return }
                apply(capabilities)
                errorMessage = nil
            } catch {
                guard expected == generation else { return }
                if let cameraError = error as? CameraError, case .configurationLost = cameraError {
                    isReady = false
                    endOrientationTracking()
                    errorMessage = cameraError.localizedDescription
                } else {
                    errorMessage = "The camera could not apply that setting. The previous mode is still selected."
                }
            }
        }
    }

    /// Lock/background paths cancel rather than commit an incomplete recording.
    func stop() {
        generation = UUID()
        engine.stop()
        endOrientationTracking()
        isStarting = false
        isConfiguring = false
        isReady = false
        isRecording = false
        isCapturing = false
        recordingSeconds = 0
        recordingBytes = 0
    }

    func capturePhoto() async {
        guard vault.isUnlocked, isReady, !isVideoMode, !isConfiguring, !isCapturing, !isRecording else { return }
        let requestGeneration = generation
        isCapturing = true
        defer { if generation == requestGeneration { isCapturing = false } }
        do {
            let photos = try await engine.capturePhoto(format: photoFormat, flash: flashMode, rotationAngle: captureRotationAngle)
            guard generation == requestGeneration else { return }
            for photo in photos {
                guard generation == requestGeneration else { return }
                let saved = try await vault.savePhoto(data: photo.data, fileExtension: photo.fileExtension, width: photo.width, height: photo.height)
                lastCaptureID = saved.id
            }
        } catch { if generation == requestGeneration { errorMessage = "The photograph could not be saved securely. Try again." } }
    }

    func startRecording() async {
        guard vault.isUnlocked, isReady, isVideoMode, !isConfiguring, !isRecording, !isCapturing, videoModes.contains(selectedVideoMode) else { return }
        isCapturing = true
        let requestGeneration = generation
        defer { if generation == requestGeneration { isCapturing = false } }
        if microphoneEnabled { microphoneEnabled = await Self.authorize(.audio) }
        guard generation == requestGeneration else { return }
        do {
            let mode = selectedVideoMode
            let writer = try await vault.beginVideo(width: mode.width, height: mode.height)
            guard generation == requestGeneration else { writer.cancel(); return }
            try await engine.startRecording(writer: writer, mode: mode, withAudio: microphoneEnabled, rotationAngle: captureRotationAngle)
            guard generation == requestGeneration else { writer.cancel(); return }
            recordingSeconds = 0
            recordingBytes = 0
            errorMessage = nil
            isRecording = true
        } catch { if generation == requestGeneration { errorMessage = "This video mode could not start securely. Try 1080p at 30 fps." } }
    }

    func stopRecording() async {
        guard isRecording, !isCapturing else { return }
        let requestGeneration = generation
        isCapturing = true
        isRecording = false
        defer { if generation == requestGeneration { isCapturing = false } }
        do {
            let (writer, duration, thumbnail) = try await engine.finishRecording()
            guard generation == requestGeneration else { writer.cancel(); return }
            let saved = try await vault.finishVideo(writer, duration: duration, thumbnail: thumbnail)
            lastCaptureID = saved.id
        } catch { if generation == requestGeneration { errorMessage = CameraError.recordingFailed.localizedDescription } }
    }

    func selectLens(_ id: String) {
        guard id != selectedLensID, let lens = availableLenses.first(where: { $0.id == id }) else { return }
        requestConfiguration(video: isVideoMode, mode: videoPreferences[lens.isFront], lensID: id)
    }
    func flipCamera() {
        guard canFlipCamera else { return }
        let target = isFrontCamera
            ? rearZoomLenses.first(where: { $0.id == lastRearLensID }) ?? rearZoomLenses.first(where: { $0.nativeZoomFactor == 1 }) ?? rearZoomLenses.first
            : availableLenses.first(where: { $0.isFront })
        if let target { selectLens(target.id) }
    }
    func focus(at point: CGPoint) { engine.focus(at: point) }
    func setExposureBias(_ value: Float) { exposureBias = value; engine.exposureBias(value) }
    func setManualExposure(iso: Float, shutterSeconds: Double) { engine.manualExposure(iso: iso, shutterSeconds: shutterSeconds) }
    func setWhiteBalance(kelvin: Float) { engine.whiteBalance(kelvin: kelvin) }
    func setWhiteBalanceGains(red: Float, green: Float, blue: Float) { engine.whiteBalanceGains(red: red, green: green, blue: blue) }
    func resetAutomaticExposure() { engine.automaticExposure() }
    func resetAutomaticWhiteBalance() { engine.automaticWhiteBalance() }
    func refreshManualCapabilities() { engine.refreshManualCapabilities() }
    func setZoom(_ factor: CGFloat) { engine.zoom(factor) }
    func resetAutomaticControls() { exposureBias = 0; engine.automaticControls(); engine.exposureBias(0) }

    private func beginOrientationTracking() {
        guard !observingOrientation else { return }
        observingOrientation = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updatePhysicalOrientation() }
            }
        updatePhysicalOrientation()
    }

    private func endOrientationTracking() {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        orientationObserver = nil
        captureRotationObservation = nil
        rotationCoordinator = nil
        if observingOrientation { UIDevice.current.endGeneratingDeviceOrientationNotifications(); observingOrientation = false }
    }

    private func configureRotationCoordinator() {
        guard rotationCoordinator?.device?.uniqueID != selectedLensID,
              let device = AVCaptureDevice(uniqueID: selectedLensID) else { return }
        captureRotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        let lensID = selectedLensID
        let expected = generation
        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor [weak self] in
                guard let self, observingOrientation, generation == expected, selectedLensID == lensID,
                      CameraPhysicalOrientation.from(UIDevice.current.orientation) != nil else { return }
                captureRotationAngle = CameraPhysicalOrientation.quarterTurn(angle, fallback: captureRotationAngle)
            }
        }
        updatePhysicalOrientation()
    }

    private func updatePhysicalOrientation() {
        // Flat/unknown readings retain the last stable direction, avoiding a jump
        // when the phone is placed on a table or during transient sensor updates.
        guard observingOrientation, let orientation = CameraPhysicalOrientation.from(UIDevice.current.orientation) else { return }
        controlRotationDegrees = orientation.controlDegrees
        captureRotationAngle = CameraPhysicalOrientation.quarterTurn(
            rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? orientation.captureDegrees,
            fallback: orientation.captureDegrees)
    }

    private static func authorize(_ mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        default: return false
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let controller: CameraController
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocus = { [weak controller] in controller?.focus(at: $0) }
        return view
    }
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== controller.session { uiView.previewLayer.session = controller.session }
        uiView.updateRotation()
    }
    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) { uiView.previewLayer.session = nil }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        accessibilityLabel = "Camera viewfinder. Tap to focus."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateRotation() }
    func updateRotation() {
        // A stationary portrait viewfinder is independent of capture metadata
        // and of the app's other tabs, which may support landscape layouts.
        if let connection = previewLayer.connection, connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
