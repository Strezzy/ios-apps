import Foundation

/// Pure scheduling and geometry. Sampling is by presentation time, never by source frame index.
struct ExportPlan: Sendable {
    struct Frame: Sendable {
        var sourceTime: Double
        var delay: Double
        var gifDelayCentiseconds: Int
    }
    var size: PixelSize
    var frames: [Frame]
    var duration: Double { frames.reduce(0) { $0 + $1.delay } }
    var estimatedWorkingBytes: Int64
    var estimatedUncompressedBytes: Int64 { Int64(size.width) * Int64(size.height) * Int64(frames.count) }

    init(project: LoopProject) throws {
        let e = project.export
        guard project.metadata.duration.isFinite, project.metadata.size.width > 0,
              project.metadata.size.height > 0, project.trimStart.isFinite, project.trimEnd.isFinite,
              project.trimStart >= 0, project.trimEnd <= project.metadata.duration + 0.002,
              project.duration >= 0.02 else {
            throw LoopError.invalidSettings("Choose a valid clip of at least 0.02 seconds.")
        }
        let ceiling = e.format.maximumFrameRate
        guard e.frameRate.isFinite, e.frameRate >= 1, e.frameRate <= ceiling,
              e.speed.isFinite, e.speed >= 0.1, e.speed <= 8,
              e.maximumDimension == 0 || (64...4096).contains(e.maximumDimension),
              [64, 128, 256].contains(e.paletteSize), (0...65535).contains(e.loopCount) else {
            throw LoopError.invalidSettings("Check the frame rate, resolution, speed and color settings.")
        }
        for overlay in project.overlays {
            guard overlay.startTime.isFinite, overlay.endTime.isFinite,
                  overlay.startTime <= overlay.endTime,
                  overlay.keyframes.allSatisfy({ $0.time.isFinite && $0.confidence.isFinite }),
                  zip(overlay.keyframes, overlay.keyframes.dropFirst()).allSatisfy({ pair in pair.0.time < pair.1.time }) else {
                throw LoopError.invalidSettings("An overlay has an invalid time range.")
            }
            if overlay.trackingEnabled && overlay.trackingNeedsReview {
                throw LoopError.invalidSettings("Review the tracked overlay before exporting. Tracking was interrupted or the clip changed.")
            }
            if overlay.trackingEnabled {
                let start = max(project.trimStart, overlay.startTime)
                let end = min(project.trimEnd, overlay.endTime)
                if end > start {
                    let sorted = overlay.keyframes.sorted { $0.time < $1.time }
                    guard let first = sorted.first, let last = sorted.last,
                          first.time <= start + 0.02, last.time >= end - 0.02,
                          sorted.allSatisfy({ $0.confidence >= 0.3 }) else {
                        throw LoopError.invalidSettings("Finish tracking the overlay across its full time range, or switch it to manual positioning and review the clip.")
                    }
                }
            }
        }
        if let tracking = project.crop.tracking, tracking.enabled {
            guard !tracking.needsReview,
                  tracking.covers(start: project.trimStart, end: project.trimEnd) else {
                throw LoopError.invalidSettings("Track the crop subject across the full selected clip, or turn off Follow subject before exporting.")
            }
        }
        let crop = project.crop.rect(source: project.metadata.size)
        let nativeWidth = max(1, Double(project.metadata.size.width) * crop.width)
        let nativeHeight = max(1, Double(project.metadata.size.height) * crop.height)
        let nativeLongEdge = max(nativeWidth, nativeHeight)
        let requested = Double(e.maximumDimension == 0 ? min(4096, Int(nativeLongEdge.rounded())) : e.maximumDimension)
        let scale = e.allowUpscaling ? requested / nativeLongEdge : min(1, requested / nativeLongEdge)
        size = PixelSize(width: max(1, Int((nativeWidth * scale).rounded())),
                         height: max(1, Int((nativeHeight * scale).rounded())))
        if e.format.isVideo { size = size.videoAligned }
        let tightestCrop = project.crop.minimumRect(source: project.metadata.size,
            from: project.trimStart, through: project.trimEnd)
        let decodedLongEdge = min(Double(project.metadata.size.longEdge),
                                  max(Double(size.width) / tightestCrop.width, Double(size.height) / tightestCrop.height))
        let decodedScale = decodedLongEdge / Double(project.metadata.size.longEdge)
        let decodedPixels = Double(project.metadata.size.width) * Double(project.metadata.size.height) * decodedScale * decodedScale
        estimatedWorkingBytes = Int64(decodedPixels * 16) + Int64(size.width) * Int64(size.height) * 12

        if !(project.effects?.activeLayers.isEmpty ?? true) {
            estimatedWorkingBytes += Int64(decodedPixels * 16)
        }
        let seam = CreativeMotion.seamDuration(project)
        if e.hdrOutput == true && e.format != .hevc { throw LoopError.invalidSettings("HDR output requires HEVC video.") }
        if e.transparentBackground == true && e.format != .apng && e.format != .hevcAlpha { throw LoopError.invalidSettings("Choose APNG or Transparent video to keep a transparent background.") }
        if let motion=project.motion, motion.mode != "off", motion.referenceAsset == nil {
            throw LoopError.invalidSettings("Choose a still frame in Motion before exporting a cinemagraph.")
        }
        let scene=project.effects?.scene ?? SceneSettings()
        var used=Set((project.effects?.tracks ?? []).filter { $0.enabled }.compactMap(\.subjectID))
        if let motion=project.motion, motion.mode != "off" || motion.echoCount > 0, let id=motion.subjectID { used.insert(id) }
        if e.format == .hevcAlpha || e.transparentBackground == true, let id=scene.selectedID { used.insert(id) }
        for id in used {
            guard let subject=scene.subjects.first(where:{$0.id==id}) else {
                throw LoopError.invalidSettings("An effect uses a removed subject. Choose another subject or Whole clip in the effect card.")
            }
            guard subject.covers(project.trimStart+seam), subject.covers(project.trimEnd-0.002) else {
                throw LoopError.invalidSettings("Track \(subject.name) across the selected clip, or choose Everyone before exporting.")
            }
        }
        let forwardDuration = (project.duration-seam) / e.speed
        let countDouble = ceil(forwardDuration * e.frameRate - 0.0000001)
        guard countDouble.isFinite, countDouble <= 30_000 else {
            throw LoopError.invalidSettings("This export would exceed 30,000 frames. Trim the clip, increase its speed or lower its frame rate.")
        }
        let count = max(1, Int(countDouble))
        var times = (0..<count).map { project.trimStart + seam + Double($0) * e.speed / e.frameRate }
        var delays = (0..<count).map { index in min(1 / e.frameRate, max(0.000001, forwardDuration - Double(index) / e.frameRate)) }
        if e.playback == .reverse {
            times.reverse()
            delays.reverse()
        } else if e.playback == .bounce, count > 2 {
            // The first and last frame are not duplicated at either turn.
            times += Array(times.dropFirst().dropLast().reversed())
            delays += Array(delays.dropFirst().dropLast().reversed())
        }
        guard times.count <= 30_000 else {
            throw LoopError.invalidSettings("Ping-pong doubles most frames. Shorten the clip or lower its frame rate.")
        }
        var idealBoundary = 0.0
        var encodedBoundary = 0
        frames = zip(times, delays).map { time, delay in
            idealBoundary += delay * 100
            let next = max(encodedBoundary + 1, Int(idealBoundary.rounded()))
            let centiseconds = next - encodedBoundary
            encodedBoundary = next
            return Frame(sourceTime: min(project.trimEnd - 1.0 / 60_000, time),
                         delay: e.format == .gif ? Double(centiseconds) / 100 : delay,
                         gifDelayCentiseconds: centiseconds)
        }
    }
}
