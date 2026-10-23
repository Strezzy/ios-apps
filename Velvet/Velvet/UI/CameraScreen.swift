import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @ObservedObject var controller: CameraController
    var startsCaptureSession = true
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vault: VaultStore
    @State private var showGrid = false
    @State private var controls = false
    @State private var timer = 0
    @State private var countdown = 0
    @State private var captureTask: Task<Void, Never>?

    private var video: Bool { controller.isVideoMode }
    private var controlsUnavailable: Bool {
        controller.isRecording || controller.isCapturing || controller.isConfiguring || countdown > 0
    }
    private var controlAngle: Angle { .degrees(controller.controlRotationDegrees) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let frame = CameraViewfinderLayout.frame(in: geometry.size, video: video)
                ZStack(alignment: .top) {
                    Color.black
                    ZStack {
                        CameraPreview(controller: controller)
                        if showGrid { CameraGrid().allowsHitTesting(false) }
                        if !controller.isReady {
                            VStack(spacing: 12) {
                                Image(systemName: "camera").font(.title)
                                Text(controller.errorMessage ?? "Starting camera…")
                                    .font(.subheadline).multilineTextAlignment(.center)
                                if controller.errorMessage != nil && !controller.isConfiguring {
                                    Button("Restart camera") { Task { await controller.start() } }
                                        .buttonStyle(.glass)
                                }
                            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                        }
                        if countdown > 0 {
                            Text("\(countdown)").font(.system(size: 80, weight: .light))
                                .rotationEffect(controlAngle).shadow(radius: 20)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityIdentifier("camera.viewfinder")

                    VStack(spacing: 0) {
                        topControls.frame(height: CameraViewfinderLayout.topBarHeight)
                        Spacer(minLength: 0)
                        VStack(spacing: 12) {
                            zoomControls.frame(height: 44)
                            modeControls.frame(height: 28)
                            captureControls.frame(height: 84)
                        }
                        .padding(.top, 28).padding(.bottom, 12)
                        .background {
                            if video {
                                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }.clipped()
            }
            .background(.black)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $controls) { cameraControls.presentationDetents([.medium, .large]) }
            .task { if startsCaptureSession { await controller.start() } }
            .onDisappear { captureTask?.cancel(); countdown = 0; controller.stop() }
            .onChange(of: controller.lastCaptureID) { _, id in if let id { Task { await model.index(id) } } }
            .onChange(of: controller.errorMessage) { _, value in if let value { model.error = value } }
        }
    }

    private var topControls: some View {
        HStack {
            if video {
                Button { controller.microphoneEnabled.toggle() } label: {
                    Image(systemName: controller.microphoneEnabled ? "mic" : "mic.slash")
                        .rotationEffect(controlAngle).frame(width: 44, height: 44)
                }.accessibilityLabel(controller.microphoneEnabled ? "Mute microphone" : "Enable microphone")
                    .disabled(controlsUnavailable)
            } else {
                Menu {
                    Picker("Flash", selection: $controller.flashMode) {
                        Text("Off").tag(CameraFlash.off)
                        Text("Auto").tag(CameraFlash.auto)
                        Text("On").tag(CameraFlash.on)
                    }
                } label: {
                    Image(systemName: controller.flashMode == .off ? "bolt.slash" : "bolt.fill")
                        .foregroundStyle(controller.flashMode == .off ? .white : VelvetTheme.accent)
                        .rotationEffect(controlAngle).frame(width: 44, height: 44)
                }.accessibilityLabel("Flash").disabled(controlsUnavailable)
            }
            Spacer()
            if controller.isRecording {
                HStack(spacing: 7) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text(Duration.seconds(controller.recordingSeconds).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }.font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Recording \(Int(controller.recordingSeconds)) seconds")
            } else if video {
                Menu {
                    Picker("Video format", selection: videoModeBinding) {
                        ForEach(controller.videoModes) { mode in Text(mode.label).tag(mode) }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(controller.selectedVideoMode.height == 2160 ? "4K" : "\(controller.selectedVideoMode.height)p")
                        Text("\(controller.selectedVideoMode.fps)").monospacedDigit()
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }.font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
                }.accessibilityLabel("Video format, \(controller.selectedVideoMode.label)")
                    .disabled(controlsUnavailable)
            } else {
                HStack(spacing: 8) {
                    Text(controller.photoFormat.label)
                    if timer > 0 { Label("\(timer)s", systemImage: "timer") }
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { controls = true } label: {
                Image(systemName: "slider.horizontal.3").rotationEffect(controlAngle).frame(width: 44, height: 44)
            }.accessibilityLabel("Camera settings").disabled(controlsUnavailable)
        }
        .font(.system(size: 18, weight: .regular)).foregroundStyle(.white).buttonStyle(.plain)
        .padding(.horizontal, 12).background(.black)
        .animation(.easeInOut(duration: 0.2), value: controller.controlRotationDegrees)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            if controller.isFrontCamera {
                Text("1×").font(.system(size: 14, weight: .semibold))
                    .rotationEffect(controlAngle).frame(width: 40, height: 40)
                    .accessibilityLabel("Front camera")
            } else {
                ForEach(controller.rearZoomLenses) { lens in
                    Button { controller.selectLens(lens.id) } label: {
                        Text(lens.label).font(.system(size: 14, weight: .semibold))
                            .rotationEffect(controlAngle).frame(width: 40, height: 40)
                            .background {
                                if controller.selectedLensID == lens.id { Circle().fill(VelvetTheme.accent.opacity(0.9)) }
                            }
                    }
                    .accessibilityLabel("\(lens.label) camera")
                    .accessibilityAddTraits(controller.selectedLensID == lens.id ? .isSelected : [])
                }
            }
        }
        .padding(3).foregroundStyle(.white).buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .disabled(controlsUnavailable || !controller.isReady)
        .opacity(controller.availableLenses.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: controller.controlRotationDegrees)
    }

    private var modeControls: some View {
        HStack(spacing: 28) {
            Button("PHOTO") { controller.setCaptureMode(video: false) }
                .foregroundStyle(video ? .white.opacity(0.65) : VelvetTheme.accent)
                .accessibilityLabel("Photo mode").accessibilityAddTraits(!video ? .isSelected : [])
            Button("VIDEO") { controller.setCaptureMode(video: true) }
                .foregroundStyle(video ? VelvetTheme.accent : .white.opacity(0.65))
                .accessibilityLabel("Video mode").accessibilityAddTraits(video ? .isSelected : [])
        }.font(.system(size: 12, weight: .semibold)).tracking(1.2).buttonStyle(.plain)
            .disabled(controlsUnavailable || !controller.isReady)
    }

    private var captureControls: some View {
        HStack {
            Button { model.tab = 1 } label: {
                if let item = vault.items.first(where: { $0.trashedAt == nil }) {
                    VaultThumbnail(item: item).frame(width: 46, height: 46)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
                } else {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 22)).frame(width: 46, height: 46)
                }
            }.accessibilityLabel("Open Photos").disabled(controlsUnavailable)
            Spacer()
            Button(action: shutter) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 78, height: 78)
                    if controller.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(video ? Color.red : .white).frame(width: 66, height: 66)
                    }
                    if controller.isConfiguring || controller.isCapturing { ProgressView().tint(video ? .white : .black) }
                }
            }
            .accessibilityLabel(controller.isRecording ? "Stop recording" : video ? "Record video" : "Take photo")
            .accessibilityIdentifier("camera.shutter")
            .disabled(!controller.isReady || controller.isCapturing || controller.isConfiguring || countdown > 0 || model.aiBusy)
            Spacer()
            Button { controller.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 23, weight: .regular)).rotationEffect(controlAngle)
                    .frame(width: 46, height: 46)
            }.accessibilityLabel(controller.isFrontCamera ? "Switch to rear camera" : "Switch to front camera")
                .disabled(controlsUnavailable || !controller.canFlipCamera || !controller.isReady)
        }.foregroundStyle(.white).buttonStyle(.plain).padding(.horizontal, 34)
            .animation(.easeInOut(duration: 0.2), value: controller.controlRotationDegrees)
    }

    private var videoModeBinding: Binding<VideoMode> {
        Binding(get: { controller.selectedVideoMode }, set: { controller.selectVideoMode($0) })
    }

    private func shutter() {
        guard !model.aiBusy else { return }
        captureTask = Task {
            if video {
                if controller.isRecording { await controller.stopRecording() } else { await controller.startRecording() }
            } else {
                countdown = timer
                while countdown > 0 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { countdown = 0; return }
                    countdown -= 1
                }
                guard !Task.isCancelled else { return }
                await controller.capturePhoto()
            }
        }
    }

    private var cameraControls: some View {
        NavigationStack {
            Form {
                Section("Composition") { Toggle("Grid", isOn: $showGrid) }
                Section("Exposure") {
                    HStack { Text("Compensation"); Spacer(); Text(String(format: "%+.1f EV", controller.exposureBias)).monospacedDigit() }
                    Slider(value: Binding(get: { Double(controller.exposureBias) }, set: { controller.setExposureBias(Float($0)) }), in: Double(min(controller.minimumExposureBias, -0.1))...Double(max(controller.maximumExposureBias, 0.1)), step: 0.1)
                        .disabled(controller.manualCapabilities?.exposureIsManual == true)
                    Text("Tap the preview to set focus and exposure.").font(.caption).foregroundStyle(.secondary)
                }
                if video {
                    Section("Video") {
                        Picker("Format", selection: videoModeBinding) {
                            ForEach(controller.videoModes) { mode in Text(mode.label).tag(mode) }
                        }
                        Toggle("Microphone", isOn: $controller.microphoneEnabled)
                    }.disabled(controlsUnavailable)
                } else {
                    Section("Photo") {
                        Picker("Format", selection: $controller.photoFormat) {
                            if controller.supportsHEIF { Text("HEIF").tag(PhotoFormat.heif) }
                            Text("JPEG").tag(PhotoFormat.jpeg)
                            if controller.supportsRAW { Text("RAW + JPEG").tag(PhotoFormat.raw) }
                        }
                        Picker("Flash", selection: $controller.flashMode) {
                            Text("Off").tag(CameraFlash.off); Text("Auto").tag(CameraFlash.auto); Text("On").tag(CameraFlash.on)
                        }
                        Picker("Timer", selection: $timer) { Text("Off").tag(0); Text("3 seconds").tag(3); Text("10 seconds").tag(10) }
                    }
                    ManualCameraControls(controller: controller)
                }
            }.navigationTitle("Camera settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controls = false } } }
        }
    }
}

/// Preserves the complete 4:3 photo / 16:9 video field of view in portrait UI
/// coordinates. Controls overlay video; rotating the phone never reshapes it.
enum CameraViewfinderLayout {
    static let topBarHeight: CGFloat = 44
    static let photoControlsHeight: CGFloat = 148
    static func frame(in size: CGSize, video: Bool) -> CGRect {
        let aspect: CGFloat = video ? 9.0 / 16.0 : 3.0 / 4.0
        let availableHeight = max(1, size.height - topBarHeight - (video ? 0 : photoControlsHeight))
        let width = min(max(1, size.width), availableHeight * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: topBarHeight, width: width, height: height)
    }
}

private struct ManualCameraControls: View {
    @ObservedObject var controller: CameraController
    @State private var manualExposure = false
    @State private var lockedWhiteBalance = false
    @State private var iso: Double = 100
    @State private var shutterSeconds: Double = 1.0 / 60
    @State private var red: Double = 1
    @State private var green: Double = 1
    @State private var blue: Double = 1

    var body: some View {
        Group {
            if let capabilities = controller.manualCapabilities {
                if capabilities.supportsExposure {
                    Section("Manual exposure") {
                        Toggle("Lock ISO and shutter", isOn: Binding(get: { manualExposure }, set: { value in
                            manualExposure = value
                            if value { applyExposure() } else { controller.resetAutomaticExposure() }
                        }))
                        if manualExposure {
                            LabeledContent("ISO", value: "\(Int(iso.rounded()))")
                            Slider(value: Binding(get: { log2(max(iso, Double(capabilities.minimumISO))) }, set: {
                                iso = pow(2, $0); applyExposure()
                            }), in: log2(Double(capabilities.minimumISO))...log2(Double(capabilities.maximumISO)))
                                .accessibilityLabel("ISO")
                            LabeledContent("Shutter", value: shutterLabel)
                            Slider(value: Binding(get: { log2(max(shutterSeconds, capabilities.minimumShutterSeconds)) }, set: {
                                shutterSeconds = pow(2, $0); applyExposure()
                            }), in: log2(capabilities.minimumShutterSeconds)...log2(capabilities.maximumShutterSeconds))
                                .accessibilityLabel("Shutter duration")
                            Text("Limits come from the active lens and photo format. Tap-to-focus restores automatic exposure.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if capabilities.supportsWhiteBalance {
                    Section("White balance") {
                        Toggle("Lock color gains", isOn: Binding(get: { lockedWhiteBalance }, set: { value in
                            lockedWhiteBalance = value
                            if value { applyWhiteBalance() } else { controller.resetAutomaticWhiteBalance() }
                        }))
                        if lockedWhiteBalance {
                            gainSlider("Red", value: $red, maximum: Double(capabilities.maximumWhiteBalanceGain))
                            gainSlider("Green", value: $green, maximum: Double(capabilities.maximumWhiteBalanceGain))
                            gainSlider("Blue", value: $blue, maximum: Double(capabilities.maximumWhiteBalanceGain))
                            Text("Hardware channel gains, constrained to this camera’s supported range. Return to automatic for a neutral starting point.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("Reset automatic focus, exposure and color") {
                        manualExposure = false
                        lockedWhiteBalance = false
                        controller.resetAutomaticControls()
                    }
                }
            }
        }
        .disabled(controller.isCapturing || controller.isRecording)
        .onAppear {
            manualExposure = controller.manualCapabilities?.exposureIsManual ?? false
            lockedWhiteBalance = controller.manualCapabilities?.whiteBalanceIsLocked ?? false
            seedValues(force: true)
            controller.refreshManualCapabilities()
        }
        .onChange(of: controller.manualCapabilities) { _, _ in seedValues(force: false) }
        .onChange(of: controller.selectedLensID) { _, _ in
            manualExposure = false
            lockedWhiteBalance = false
            seedValues(force: true)
        }
    }

    private var shutterLabel: String {
        shutterSeconds < 1 ? "1/\(Int((1 / shutterSeconds).rounded())) s" : String(format: "%.2f s", shutterSeconds)
    }
    private func applyExposure() { controller.setManualExposure(iso: Float(iso), shutterSeconds: shutterSeconds) }
    private func applyWhiteBalance() { controller.setWhiteBalanceGains(red: Float(red), green: Float(green), blue: Float(blue)) }
    private func seedValues(force: Bool) {
        guard let capabilities = controller.manualCapabilities else { return }
        if force || !manualExposure {
            iso = min(Double(capabilities.maximumISO), max(Double(capabilities.minimumISO), Double(capabilities.currentISO)))
            shutterSeconds = min(capabilities.maximumShutterSeconds, max(capabilities.minimumShutterSeconds, capabilities.currentShutterSeconds))
        }
        if force || !lockedWhiteBalance {
            let maximum = Double(capabilities.maximumWhiteBalanceGain)
            red = min(maximum, max(1, Double(capabilities.redGain)))
            green = min(maximum, max(1, Double(capabilities.greenGain)))
            blue = min(maximum, max(1, Double(capabilities.blueGain)))
        }
    }
    private func gainSlider(_ title: String, value: Binding<Double>, maximum: Double) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: String(format: "%.2f×", value.wrappedValue))
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; applyWhiteBalance() }), in: 1...maximum)
                .accessibilityLabel("\(title) white balance gain")
        }
    }
}

private struct CameraGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for n in 1...2 {
                    let x = geometry.size.width * CGFloat(n) / 3
                    let y = geometry.size.height * CGFloat(n) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }.stroke(.white.opacity(0.23), lineWidth: 0.5)
        }
    }
}
