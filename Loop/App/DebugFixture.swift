#if DEBUG
import AVFoundation
import CoreGraphics

enum DebugFixture {
    static func makeVideo() async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LoopFixture-\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 480, AVVideoHeightKey: 270])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 270, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? LoopError.encoding("Could not create the test video.") }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<120 {
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard let pool = adaptor.pixelBufferPool else { throw LoopError.encoding("Missing test pixel buffer pool.") }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw LoopError.encoding("Could not create a test frame.") }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 480, height: 270, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
                    context.setFillColor(CGColor(red: 0.71, green: 0.89, blue: 0.84, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 480, height: 270))
                    context.setFillColor(CGColor(red: 0.99, green: 0.85, blue: 0.46, alpha: 1)); context.fillEllipse(in: CGRect(x: 340, y: 173, width: 58, height: 58))
                    for layer in 0..<5 {
                        let base = Double(layer) * 24 + 40
                        context.setFillColor(CGColor(red: 0.015 + Double(layer) * 0.018, green: 0.32 + Double(layer) * 0.075, blue: 0.36 + Double(layer) * 0.055, alpha: 1))
                        context.beginPath(); context.move(to: CGPoint(x: 0, y: 0)); context.addLine(to: CGPoint(x: 0, y: base))
                        for x in stride(from: 0, through: 480, by: 8) {
                            let y = base + sin(Double(x) / 65 + Double(index) / 12 + Double(layer)) * 14
                            context.addLine(to: CGPoint(x: Double(x), y: y))
                        }
                        context.addLine(to: CGPoint(x: 480, y: 0)); context.closePath(); context.fillPath()
                    }
                    let boatX = 100 + Double(index) * 2.5
                    context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.86, alpha: 1))
                    context.beginPath(); context.move(to: CGPoint(x: boatX, y: 130)); context.addLine(to: CGPoint(x: boatX + 38, y: 130)); context.addLine(to: CGPoint(x: boatX + 28, y: 118)); context.addLine(to: CGPoint(x: boatX + 10, y: 118)); context.closePath(); context.fillPath()
                    context.beginPath(); context.move(to: CGPoint(x: boatX + 20, y: 134)); context.addLine(to: CGPoint(x: boatX + 20, y: 188)); context.addLine(to: CGPoint(x: boatX + 48, y: 136)); context.closePath(); context.fillPath()
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60)) else { throw writer.error ?? LoopError.encoding("Could not append a test frame.") }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LoopError.encoding("The test video did not finish.") }
            return url
        }.value
    }

    /// A real 3840×2160, 60 FPS asset for high-resolution decoder and tracking tests.
    /// Its moving texture stays inside the default portrait subject-selection box at t=0.
    static func make4K60TrackingVideo(frameCount: Int = 120) async throws -> URL {
        let count = max(2, frameCount)
        return try await Task.detached(priority: .userInitiated) {
            let width = 3840, height = 2160
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Loop4K60-\(UUID().uuidString).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 24_000_000,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ])
            guard writer.canAdd(input) else { throw LoopError.encoding("4K fixture encoder is unavailable.") }
            writer.add(input)
            var finished = false
            defer {
                if !finished { writer.cancelWriting(); try? FileManager.default.removeItem(at: url) }
            }
            guard writer.startWriting() else { throw writer.error ?? LoopError.encoding("Could not start the 4K fixture.") }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<count {
                let began = Date()
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    if let error = writer.error { throw error }
                    guard Date().timeIntervalSince(began) < 30 else {
                        throw LoopError.encoding("The 4K fixture encoder did not become ready.")
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
                try Task.checkCancellation()
                try autoreleasepool {
                    guard let pool = adaptor.pixelBufferPool else { throw LoopError.encoding("Missing 4K fixture buffer pool.") }
                    var rawBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rawBuffer) == kCVReturnSuccess,
                          let buffer = rawBuffer else { throw LoopError.encoding("Could not create a 4K fixture frame.") }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                        width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
                    else { throw LoopError.encoding("Could not draw a 4K fixture frame.") }
                    context.setFillColor(CGColor(red: 0.71, green: 0.89, blue: 0.84, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    // Fixed context marks make a moving crop visibly distinct from a static crop.
                    context.setFillColor(CGColor(red: 0.99, green: 0.85, blue: 0.46, alpha: 1))
                    context.fillEllipse(in: CGRect(x: 2800, y: 1580, width: 320, height: 320))
                    context.setFillColor(CGColor(red: 0.02, green: 0.39, blue: 0.43, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: width, height: 300))
                    let rect = trackingSubjectRect(frame: index, frameCount: count)
                    let box = CGRect(x: rect.x * Double(width),
                                     y: (1 - rect.y - rect.height) * Double(height),
                                     width: rect.width * Double(width), height: rect.height * Double(height))
                    for row in 0..<7 {
                        for column in 0..<5 {
                            let dark = (row + column).isMultiple(of: 2)
                            context.setFillColor(dark
                                ? CGColor(red: 0.02, green: 0.23, blue: 0.28, alpha: 1)
                                : CGColor(red: 1, green: 0.98, blue: 0.86, alpha: 1))
                            context.fill(CGRect(x: box.minX + Double(column) * box.width / 5,
                                y: box.minY + Double(row) * box.height / 7,
                                width: box.width / 5 + 1, height: box.height / 7 + 1))
                        }
                    }
                    // The asymmetric mark disambiguates neighboring texture cells.
                    context.setFillColor(CGColor(red: 0.98, green: 0.31, blue: 0.15, alpha: 1))
                    context.fillEllipse(in: CGRect(x: box.minX + box.width * 0.08,
                        y: box.minY + box.height * 0.66, width: box.width * 0.3, height: box.width * 0.3))
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60)) else {
                        throw writer.error ?? LoopError.encoding("Could not append a 4K fixture frame.")
                    }
                }
            }
            writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: 60))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LoopError.encoding("The 4K fixture did not finish.") }
            finished = true
            return url
        }.value
    }

    static func trackingSubjectRect(frame: Int, frameCount: Int = 120) -> NormalizedRect {
        let fraction = min(1, max(0, Double(frame) / Double(max(1, frameCount - 1))))
        let scale = 1 + fraction * 0.15
        let width = 0.18 * scale, height = 0.42 * scale
        let centerX = 0.5 + fraction * 0.18
        return NormalizedRect(x: centerX - width / 2, y: 0.5 - height / 2,
                              width: width, height: height)
    }

}
#endif
