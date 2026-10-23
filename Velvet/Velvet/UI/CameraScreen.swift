import SwiftUI
import AVFoundation

struct CameraScreen: View {
    @ObservedObject var controller: CameraController
    var startsCaptureSession = true
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomSelection
    @AppStorage("camera.showGrid") private var showGrid = false
    @State private var controls = false
    @AppStorage("camera.timer") private var timer = 0
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
                            .opacity(controller.isLensTransitioning ? 0.82 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.isLensTransitioning)
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
                videoFormatControls
            } else {
                photoFormatControls
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
                                if controller.selectedLensID == lens.id {
                                    Circle().fill(VelvetTheme.accent.opacity(0.9))
                                        .matchedGeometryEffect(id: "selectedLens", in: zoomSelection)
                                }
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: controller.selectedLensID)
        .animation(.easeInOut(duration: 0.2), value: controller.controlRotationDegrees)
    }

    private var photoFormatControls: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Photo format", selection: $controller.photoFormat) {
                    if controller.supportsHEIF { Text("HEIF").tag(PhotoFormat.heif) }
                    Text("JPEG").tag(PhotoFormat.jpeg)
                    if controller.supportsRAW { Text("RAW + JPEG").tag(PhotoFormat.raw) }
                }
            } label: {
                Text(controller.photoFormat == .raw ? "JPEG +" : controller.photoFormat.label)
                    .frame(minHeight: 44)
            }.accessibilityLabel("Photo format, \(controller.photoFormat.label)")
            if controller.supportsRAW {
                Button {
                    controller.photoFormat = controller.photoFormat == .raw
                        ? (controller.supportsHEIF ? .heif : .jpeg) : .raw
                } label: {
                    Text("RAW").strikethrough(controller.photoFormat != .raw, color: .white.opacity(0.7))
                        .foregroundStyle(controller.photoFormat == .raw ? VelvetTheme.accent : .white.opacity(0.65))
                        .frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("RAW photo")
                    .accessibilityValue(controller.photoFormat == .raw ? "On, RAW and JPEG" : "Off")
                    .accessibilityHint("Saves a RAW photo and a JPEG copy")
                    .accessibilityIdentifier("camera.rawPhoto")
            }
            if timer > 0 { Label("\(timer)s", systemImage: "timer").labelStyle(.titleAndIcon) }
        }.font(.system(size: 12, weight: .semibold))
            .disabled(controlsUnavailable)
    }

    private var videoFormatControls: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(Array(Set(controller.videoModes.map(\.height))).sorted(by: >), id: \.self) { height in
                    Button(height == 2160 ? "4K" : "\(height)p") {
                        let modes = controller.videoModes.filter { $0.height == height }
                        let rates = Set(modes.map(\.fps))
                        let fps = rates.contains(controller.selectedVideoMode.fps)
                            ? controller.selectedVideoMode.fps : (rates.filter { $0 <= 60 }.max() ?? 30)
                        selectVideoFormat(height: height, fps: fps)
                    }
                }
            } label: {
                Text(controller.selectedVideoMode.height == 2160 ? "4K" : "\(controller.selectedVideoMode.height)p")
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Video resolution, \(controller.selectedVideoMode.height == 2160 ? "4K" : "\(controller.selectedVideoMode.height)p")")
            Menu {
                ForEach(Array(Set(controller.videoModes.filter { $0.height == controller.selectedVideoMode.height }.map(\.fps))).sorted(), id: \.self) { fps in
                    Button("\(fps) fps") { selectVideoFormat(height: controller.selectedVideoMode.height, fps: fps) }
                }
            } label: {
                Text("\(controller.selectedVideoMode.fps)").monospacedDigit()
                    .foregroundStyle(controller.selectedVideoMode.fps > 60 ? VelvetTheme.accent : .white)
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Frame rate, \(controller.selectedVideoMode.fps) frames per second")
                .accessibilityIdentifier("camera.frameRate")
        }.font(.system(size: 13, weight: .semibold)).disabled(controlsUnavailable)
    }

    private func selectVideoFormat(height: Int, fps: Int) {
        let modes = controller.videoModes.filter { $0.height == height && $0.fps == fps }
        if let mode = modes.first(where: { $0.codec == controller.selectedVideoMode.codec })
            ?? modes.first(where: { $0.codec == "hevc" }) ?? modes.first {
            controller.selectVideoMode(mode)
        }
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
                Section { Toggle("Grid", isOn: $showGrid) }
                if video {
                    Section("Video") {
                        Picker("Format", selection: videoModeBinding) {
                            ForEach(controller.videoModes) { mode in Text(mode.label).tag(mode) }
                        }
                        Toggle("Microphone", isOn: $controller.microphoneEnabled)
                        Text("RAW video is not available.").font(.caption).foregroundStyle(.secondary)
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
                }
                exposureControls
                if !video {
                    Section {
                        NavigationLink("Manual controls") {
                            Form { ManualCameraControls(controller: controller) }
                                .navigationTitle("Manual controls").navigationBarTitleDisplayMode(.inline)
                        }
                    }.disabled(controlsUnavailable)
                }
            }.navigationTitle("Camera settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controls = false } } }
        }
    }

    private var exposureControls: some View {
        Section {
            Stepper(onIncrement: { adjustExposure(by: 1.0 / 3.0) }, onDecrement: { adjustExposure(by: -1.0 / 3.0) }) {
                LabeledContent("Exposure", value: String(format: "%+.1f EV", controller.exposureBias))
                    .monospacedDigit()
            }
            .disabled(controlsUnavailable || controller.manualCapabilities?.exposureIsManual == true ||
                      controller.maximumExposureBias <= controller.minimumExposureBias)
            if abs(controller.exposureBias) > 0.01 {
                Button("Reset exposure") { controller.setExposureBias(0) }
                    .disabled(controlsUnavailable || controller.manualCapabilities?.exposureIsManual == true)
            }
        } footer: {
            Text(controller.manualCapabilities?.exposureIsManual == true
                 ? "Turn off manual exposure to adjust brightness here."
                 : "Tap the viewfinder to focus. Exposure adjusts brightness.")
        }
    }

    private func adjustExposure(by amount: Float) {
        let requested = (controller.exposureBias * 3).rounded() / 3 + amount
        controller.setExposureBias(min(controller.maximumExposureBias, max(controller.minimumExposureBias, requested)))
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
                            Text("Tap-to-focus keeps these exposure settings. Turn off the lock to return to automatic exposure.")
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
