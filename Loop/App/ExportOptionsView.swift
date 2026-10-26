import SwiftUI

struct ExportOptionsView: View {
    @Binding var project: LoopProject
    var body: some View {
        VStack(spacing: 16) {
            LoopCard {
                EditorSectionTitle(title: "Your loop, your way")
                Picker("Format", selection: $project.export.format) {
                    ForEach(AnimationFormat.allCases) { format in Text(format.title).tag(format) }
                }.pickerStyle(.segmented).accessibilityIdentifier("exportFormat")
                Text(project.export.format.detailDescription)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Frame rate").font(.subheadline)
                    Spacer()
                    Text("\(LoopFormat.rate(project.export.frameRate)) FPS").font(.subheadline.monospacedDigit()).foregroundStyle(LoopTheme.teal)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach([12.0, 15, 24, 30, 50, 60], id: \.self) { rate in
                            Button(LoopFormat.rate(rate)) { project.export.frameRate = rate }
                                .buttonStyle(.glass).tint(abs(project.export.frameRate - rate) < 0.01 ? LoopTheme.teal : .secondary)
                                .accessibilityIdentifier("fps-\(Int(rate))")
                        }
                        Button("Source") {
                            project.export.frameRate = min(project.export.format.maximumFrameRate, max(1, project.metadata.nominalFrameRate))
                        }.buttonStyle(.glass)
                    }.padding(2)
                }
                Stepper(value: $project.export.frameRate, in: 1...(project.export.format.maximumFrameRate), step: 1) {
                    Text("Custom: \(LoopFormat.rate(project.export.frameRate)) FPS").font(.subheadline)
                }
                if project.export.format == .gif {
                    Label(project.export.frameRate > 50 ? "High-frame-rate GIF: delays alternate in 10 ms steps. Some viewers slow these down. Choose APNG for precise timing." : "GIF timing uses 10 ms steps. Loop preserves overall timing as closely as the format allows.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if project.export.frameRate * project.export.speed > max(1, project.metadata.nominalFrameRate) + 0.01 {
                    Text("The chosen rate exceeds the available source frames at this speed. Frames may repeat; no motion interpolation is added.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LoopCard {
                EditorSectionTitle(title: "Keep the detail", subtitle: "Resolution is the longest edge. The crop sets the other dimension.")
                Picker("Resolution", selection: $project.export.maximumDimension) {
                    Text("Native crop · up to 4096 px").tag(0)
                    ForEach([480, 720, 1080, 1440, 2160, 3840, 4096], id: \.self) { value in Text("\(value) px").tag(value) }
                    if ![0, 480, 720, 1080, 1440, 2160, 3840, 4096].contains(project.export.maximumDimension) {
                        Text("Custom · \(project.export.maximumDimension) px").tag(project.export.maximumDimension)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("exportResolution")
                if project.export.maximumDimension != 0 {
                    Stepper(value: $project.export.maximumDimension, in: 64...4096, step: 16) {
                        Text("Custom edge: \(project.export.maximumDimension) px").font(.subheadline)
                    }
                }
                Toggle("Allow enlargement", isOn: $project.export.allowUpscaling)
                Text("Enlargement increases pixel dimensions, not captured detail. Very large animations can take time and create large files.")
                    .font(.caption).foregroundStyle(.secondary)
                if project.metadata.isHDR {
                    Label("HDR is converted to standard color for export; HDR and Dolby Vision metadata are not preserved.", systemImage: "sun.max")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if project.export.format == .gif {
                LoopCard {
                    EditorSectionTitle(title: "Color & texture")
                    Picker("Colors per frame", selection: $project.export.paletteSize) {
                        Text("64").tag(64); Text("128").tag(128); Text("256").tag(256)
                    }.pickerStyle(.segmented)
                    Toggle("Dither gradients", isOn: $project.export.dither)
                    Text("More colors keep subtle detail. Dithering softens color bands with a fine texture and may increase file size.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LoopCard {
                EditorSectionTitle(title: project.export.format.isVideo ? "Video options" : "On repeat")
                if project.export.format.isVideo {
                    Toggle("Include audio", isOn: Binding(get: { project.export.includeAudio != false }, set: { project.export.includeAudio = $0 }))
                        .disabled(project.export.playback != .forward)
                    Text(project.export.playback == .forward
                        ? "Audio follows the selected clip and speed when a source audio track is available. Video files play once; repeat playback is controlled by the player."
                        : "Reverse and ping-pong videos export silently. Switch to forward playback to include audio.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Video encoding uses even pixel dimensions; an odd edge is rounded down by one pixel.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                Toggle("Loop forever", isOn: Binding(get: { project.export.loopCount == 0 }, set: { project.export.loopCount = $0 ? 0 : 1 }))
                if project.export.loopCount > 0 {
                    Stepper("Play \(project.export.loopCount) time\(project.export.loopCount == 1 ? "" : "s")", value: $project.export.loopCount, in: 1...100)
                }
                }
                outputSummary
            }
        }.onChange(of: project.export.format) { _, value in
            project.export.frameRate = min(value.maximumFrameRate, project.export.frameRate)
        }
    }

    @ViewBuilder private var outputSummary: some View {
        if let plan = try? ExportPlan(project: project) {
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.size.label).font(.title3.weight(.bold)).monospacedDigit()
                    Text("\(plan.frames.count) frames · \(LoopFormat.time(plan.duration))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(project.export.format.title).font(.caption.weight(.bold)).padding(8)
                    .background(LoopTheme.teal.opacity(0.12), in: .rect(cornerRadius: 9))
            }
            Text("Frame-processing estimate: \(LoopFormat.bytes(plan.estimatedWorkingBytes)). Final file size depends on the content and compression.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Label(validationMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
    }

    private var validationMessage: String {
        do { _ = try ExportPlan(project: project); return "" }
        catch { return error.localizedDescription }
    }
}
