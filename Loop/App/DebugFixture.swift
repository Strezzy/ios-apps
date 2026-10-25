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
            for index in 0..<60 {
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
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw writer.error ?? LoopError.encoding("Could not append a test frame.") }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LoopError.encoding("The test video did not finish.") }
            return url
        }.value
    }
}
#endif
