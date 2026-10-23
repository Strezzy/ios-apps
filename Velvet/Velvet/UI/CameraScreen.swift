import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @ObservedObject var controller: CameraController
    @EnvironmentObject private var model: AppModel
    @State private var video = false
    @State private var showGrid = true
    @State private var controls = false
    @State private var timer = 0
    @State private var countdown = 0
    @State private var captureTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    CameraPreview(controller: controller)
                    if showGrid { CameraGrid().allowsHitTesting(false) }
                    if !controller.isReady {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.aperture").font(.largeTitle)
                            Text(controller.errorMessage ?? "Preparing camera…").font(.callout).multilineTextAlignment(.center)
                        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                    }
                    VStack {
                        HStack {
                            Label("Encrypted capture", systemImage: "lock.fill").font(.caption.weight(.medium))
                            Spacer()
                            Text(video ? controller.selectedVideoMode.label : controller.photoResolutionLabel)
                                .font(.caption.monospacedDigit())
                        }.padding(14).background(.black.opacity(0.35))
                        Spacer()
                        if controller.isRecording {
                            HStack(spacing: 8) {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                Text(Duration.seconds(controller.recordingSeconds).formatted(.time(pattern: .minuteSecond)))
                                Text(ByteCountFormatter.string(fromByteCount: controller.recordingBytes, countStyle: .file)).foregroundStyle(.secondary)
                            }.font(.callout.monospacedDigit()).padding(12).glassEffect()
                        }
                        HStack(spacing: 12) {
                            ForEach(controller.availableLenses) { lens in
                                Button(lens.label) { controller.selectLens(lens.id) }
                                    .font(.subheadline.weight(.semibold)).buttonStyle(.glass)
                                    .tint(controller.selectedLensID == lens.id ? VelvetTheme.accent : .white)
                                    .disabled(controller.isRecording || controller.isCapturing)
                            }
                        }.padding(16)
                    }
                    if countdown > 0 { Text("\(countdown)").font(.system(size: 80, weight: .ultraLight)).shadow(radius: 20) }
                }.clipShape(.rect(cornerRadius: 24)).padding(.horizontal, 8)
                HStack(spacing: 28) {
                    Button("Photo") { video = false }.foregroundStyle(video ? .secondary : .primary)
                    Button("Video") { video = true }.foregroundStyle(video ? .primary : .secondary)
                }.font(.subheadline.weight(.semibold)).padding(.top, 20).disabled(controller.isRecording)
                HStack {
                    Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid" : "viewfinder").font(.title3).frame(width: 48, height: 48) }.buttonStyle(.glass).accessibilityLabel("Toggle composition grid")
                    Spacer()
                    Button(action: shutter) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.8), lineWidth: 3).frame(width: 76, height: 76)
                            if controller.isRecording { RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30) }
                            else { Circle().fill(video ? Color.red : .white).frame(width: 64, height: 64) }
                        }
                    }.buttonStyle(.plain).accessibilityLabel(controller.isRecording ? "Stop recording" : video ? "Record video" : "Take photo")
                        .disabled(!controller.isReady || controller.isCapturing || countdown > 0 || model.aiBusy)
                    Spacer()
                    Button { controls = true } label: { Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 48, height: 48) }.buttonStyle(.glass).accessibilityLabel("Camera controls")
                }.padding(.horizontal, 32).padding(.vertical, 18)
            }.background(.black).navigationTitle("Velvet").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { model.lock(); model.concealed = false } label: { Image(systemName: "lock") }.accessibilityLabel("Lock vault") } }
                .sheet(isPresented: $controls) { cameraControls.presentationDetents([.medium, .large]) }
                .task { await controller.start() }
                .onDisappear { captureTask?.cancel(); countdown = 0; controller.stop() }
                .onChange(of: controller.lastCaptureID) { _, id in if let id { Task { await model.index(id) } } }
                .onChange(of: controller.errorMessage) { _, value in if let value { model.error = value } }
        }
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
                Section("Exposure") {
                    HStack { Text("Compensation"); Spacer(); Text(String(format: "%+.1f EV", controller.exposureBias)).monospacedDigit() }
                    Slider(value: Binding(get: { Double(controller.exposureBias) }, set: { controller.setExposureBias(Float($0)) }), in: Double(min(controller.minimumExposureBias, -0.1))...Double(max(controller.maximumExposureBias, 0.1)), step: 0.1)
                        .disabled(controller.manualCapabilities?.exposureIsManual == true)
                    Text("Tap the preview to set focus and exposure.").font(.caption).foregroundStyle(.secondary)
                }
                if video {
                    Section("Recording") {
                        Picker("Format", selection: $controller.selectedVideoMode) {
                            ForEach(controller.videoModes) { mode in Text(mode.label).tag(mode) }
                        }
                        Toggle("Microphone", isOn: $controller.microphoneEnabled)
                        Text("Available modes are checked against the active camera. Professional HDR, Log and ProRes modes are unavailable until the encrypted path is validated.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(controller.isRecording)
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
                }
                if !video { ManualCameraControls(controller: controller) }
                Section { PrivacyFootnote(text: "Originals are encrypted before Velvet writes them to storage.") }
            }.navigationTitle("Camera controls").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controls = false } } }
        }
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
