import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class CameraController: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isRecording = false
    @Published private(set) var isCapturing = false
    @Published var errorMessage: String?
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var selectedLensID = ""
    @Published private(set) var videoModes: [VideoMode] = []
    @Published var selectedVideoMode = VideoMode.standard
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
    var captureRotationAngle: CGFloat = 90
    private let engine = CaptureEngine()
    private let vault: VaultStore
    private var generation = UUID()
    private var isStarting = false

    init(vault: VaultStore) {
        self.vault = vault
        engine.onCapabilities = { [weak self] capabilities in
            Task { @MainActor [weak self] in
                guard let self else { return }
                availableLenses = capabilities.lenses
                selectedLensID = capabilities.selectedLens
                videoModes = capabilities.modes
                supportsRAW = capabilities.supportsRAW
                supportsHEIF = capabilities.supportsHEIF
                photoResolutionLabel = capabilities.resolution
                minimumExposureBias = capabilities.minimumExposureBias
                maximumExposureBias = capabilities.maximumExposureBias
                if !videoModes.contains(selectedVideoMode) { selectedVideoMode = videoModes.first(where: { $0 == .standard }) ?? videoModes.first ?? .standard }
                if photoFormat == .raw && !supportsRAW { photoFormat = supportsHEIF ? .heif : .jpeg }
                if photoFormat == .heif && !supportsHEIF { photoFormat = .jpeg }
            }
        }
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
        guard !isReady, !isStarting else { return }
        isStarting = true
        let requestGeneration = generation
        defer { isStarting = false }
        let authorized = await Self.authorize(.video)
        guard generation == requestGeneration else { return }
        guard authorized else { errorMessage = CameraError.permission.localizedDescription; return }
        do {
            try await engine.start()
            guard generation == requestGeneration else { engine.stop(); return }
            isReady = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    /// Lock/background paths cancel rather than commit an incomplete recording.
    func stop() {
        generation = UUID()
        engine.stop()
        isReady = false
        isRecording = false
        isCapturing = false
        recordingSeconds = 0
        recordingBytes = 0
    }

    func capturePhoto() async {
        guard isReady, !isCapturing, !isRecording else { return }
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
        guard isReady, !isRecording, !isCapturing, videoModes.contains(selectedVideoMode) else { return }
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
            guard generation == requestGeneration else { engine.stop(); return }
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

    func selectLens(_ id: String) { guard !isRecording, !isCapturing else { return }; engine.selectLens(id) }
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
        view.onRotation = { [weak controller] in controller?.captureRotationAngle = $0 }
        return view
    }
    func updateUIView(_ uiView: CameraPreviewView, context: Context) { uiView.previewLayer.session = controller.session; uiView.updateRotation() }
    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) { uiView.previewLayer.session = nil }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onFocus: ((CGPoint) -> Void)?
    var onRotation: ((CGFloat) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        accessibilityLabel = "Camera viewfinder. Tap to focus."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); updateRotation() }
    func updateRotation() {
        let angle: CGFloat
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        onRotation?(angle)
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
