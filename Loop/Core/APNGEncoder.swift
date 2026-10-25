import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Streams APNG chunks to disk while ImageIO compresses just one RGBA frame at a
/// time. Full-canvas SOURCE frames make reverse playback and overlays deterministic.
final class APNGEncoder: AnimationWriter {
    private let output: AnimationOutputFile
    private let size: PixelSize
    private let expectedFrames: Int
    private let loopCount: Int
    private var addedFrames = 0
    private var sequence: UInt32 = 0
    private var firstHeader: Data?
    private var finished = false
    private var failed = false

    init(destination: URL, size: PixelSize, frameCount: Int, settings: ExportSettings) throws {
        try EncoderRaster.validate(size: size, frameCount: frameCount)
        guard (0...65535).contains(settings.loopCount) else {
            throw LoopError.encoding("The animation repeat count is invalid.")
        }
        self.size = size
        expectedFrames = frameCount
        loopCount = settings.loopCount
        output = try AnimationOutputFile(destination: destination)
    }

    func add(_ image: CGImage, delay: Double, gifDelayCentiseconds: Int) throws {
        guard !finished, !failed, addedFrames < expectedFrames else {
            throw LoopError.encoding("The APNG writer cannot accept another frame.")
        }
        do {
            let timing = try APNGDelay.fraction(delay)
            try autoreleasepool {
                let normalized = try EncoderRaster.image(image, size: size)
                let buffer = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(buffer as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
                    throw LoopError.encoding("The PNG compressor could not be created.")
                }
                CGImageDestinationAddImage(destination, normalized, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw LoopError.encoding("A PNG animation frame could not be compressed.")
                }
                let png = buffer as Data
                let chunks = try PNGFrame.chunks(in: png)
                guard let ihdr = chunks.first(where: { $0.type == "IHDR" }),
                      ihdr.payload.count == 13 else {
                    throw LoopError.encoding("The PNG compressor returned an invalid image header.")
                }
                let header = Data(png[ihdr.payload])
                let imageChunks = chunks.filter { $0.type == "IDAT" }
                guard !imageChunks.isEmpty else {
                    throw LoopError.encoding("The PNG compressor returned no image data.")
                }
                if addedFrames == 0 {
                    firstHeader = header
                    try output.write(PNGFrame.signature)
                    try writeChunk("IHDR", payload: header)
                    // Preserve color information, without copying comments, location,
                    // source metadata, thumbnails, or unrelated PNG extensions.
                    let colorChunks: Set<String> = ["cHRM", "gAMA", "iCCP", "sRGB"]
                    for chunk in chunks where colorChunks.contains(chunk.type) {
                        try writeChunk(chunk.type, payload: Data(png[chunk.payload]))
                    }
                    var animation: [UInt8] = []
                    animation.appendBigEndian(UInt32(expectedFrames))
                    // APNG's count is total plays; zero means forever.
                    animation.appendBigEndian(UInt32(loopCount))
                    try writeChunk("acTL", payload: Data(animation))
                } else if header != firstHeader {
                    throw LoopError.encoding("PNG frames unexpectedly use different pixel formats.")
                }

                var control: [UInt8] = []
                control.appendBigEndian(try nextSequence())
                control.appendBigEndian(UInt32(size.width))
                control.appendBigEndian(UInt32(size.height))
                control.appendBigEndian(UInt32(0)) // x offset
                control.appendBigEndian(UInt32(0)) // y offset
                control.appendBigEndian(timing.numerator)
                control.appendBigEndian(timing.denominator)
                control += [0, 0] // dispose NONE; blend SOURCE
                try writeChunk("fcTL", payload: Data(control))

                for chunk in imageChunks {
                    let compressed = Data(png[chunk.payload])
                    if addedFrames == 0 {
                        try writeChunk("IDAT", payload: compressed)
                    } else {
                        var prefix: [UInt8] = []
                        prefix.appendBigEndian(try nextSequence())
                        try writeChunk("fdAT", prefix: Data(prefix), payload: compressed)
                    }
                }
            }
            addedFrames += 1
        } catch {
            failed = true
            try? output.close()
            throw error
        }
    }

    func finish() throws {
        guard !finished, !failed else {
            throw LoopError.encoding("The APNG writer has already closed.")
        }
        do {
            guard addedFrames == expectedFrames else {
                throw LoopError.encoding("APNG export stopped before every frame was written.")
            }
            try writeChunk("IEND", payload: Data())
            try output.close()
            finished = true
        } catch {
            failed = true
            try? output.close()
            throw error
        }
    }

    private func nextSequence() throws -> UInt32 {
        guard sequence < UInt32.max else { throw LoopError.encoding("The APNG has too many data chunks.") }
        let result = sequence
        sequence += 1
        return result
    }

    private func writeChunk(_ name: String, prefix: Data = Data(), payload: Data) throws {
        let length = prefix.count + payload.count
        guard length <= Int(UInt32.max), name.utf8.count == 4 else {
            throw LoopError.encoding("A PNG data chunk is too large.")
        }
        let type = Data(name.utf8)
        var header: [UInt8] = []
        header.appendBigEndian(UInt32(length))
        header += type
        try output.write(header)
        if !prefix.isEmpty { try output.write(prefix) }
        try output.write(payload)
        var crc = PNGCRC32.update(0xffffffff, with: type)
        crc = PNGCRC32.update(crc, with: prefix)
        crc = PNGCRC32.update(crc, with: payload)
        var footer: [UInt8] = []
        footer.appendBigEndian(crc ^ 0xffffffff)
        try output.write(footer)
    }
}

private enum PNGFrame {
    static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    struct Chunk {
        let type: String
        let payload: Range<Int>
    }

    static func chunks(in data: Data) throws -> [Chunk] {
        guard data.count >= 20, data.prefix(8).elementsEqual(signature) else {
            throw LoopError.encoding("The PNG compressor returned an invalid file.")
        }
        var offset = 8
        var result: [Chunk] = []
        while offset <= data.count - 12 {
            let length = Int(data.readBigEndianUInt32(at: offset))
            guard length <= data.count - offset - 12 else {
                throw LoopError.encoding("A compressed PNG frame is truncated.")
            }
            guard let type = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii) else {
                throw LoopError.encoding("A compressed PNG frame contains an invalid chunk.")
            }
            result.append(Chunk(type: type, payload: (offset + 8)..<(offset + 8 + length)))
            offset += length + 12
            if type == "IEND" { return result }
        }
        throw LoopError.encoding("A compressed PNG frame has no end marker.")
    }
}

private enum PNGCRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value & 1) != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1 }
        return value
    }

    static func update(_ initial: UInt32, with data: Data) -> UInt32 {
        var crc = initial
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc
    }
}

/// Bounded continued-fraction approximation: common rates such as 24, 30, 60,
/// 120 and 30000/1001 retain exact rational timing in the 16-bit APNG fields.
enum APNGDelay {
    static func fraction(_ seconds: Double) throws -> (numerator: UInt16, denominator: UInt16) {
        guard seconds.isFinite, seconds > 0, seconds <= 65535 else {
            throw LoopError.encoding("The APNG frame duration is unsupported.")
        }
        let limit = 65535
        var previousNumerator = 0, numerator = 1
        var previousDenominator = 1, denominator = 0
        var remainder = seconds
        for _ in 0..<32 {
            let integral = floor(remainder)
            let nextNumerator = integral * Double(numerator) + Double(previousNumerator)
            let nextDenominator = integral * Double(denominator) + Double(previousDenominator)
            if nextNumerator > Double(limit) || nextDenominator > Double(limit) {
                let numeratorBound = numerator > 0 ? (limit - previousNumerator) / numerator : limit
                let denominatorBound = denominator > 0 ? (limit - previousDenominator) / denominator : limit
                let multiplier = max(0, min(numeratorBound, denominatorBound))
                let boundedNumerator = multiplier * numerator + previousNumerator
                let boundedDenominator = multiplier * denominator + previousDenominator
                if boundedNumerator > 0, boundedDenominator > 0,
                   denominator == 0 || numerator == 0 ||
                    abs(Double(boundedNumerator) / Double(boundedDenominator) - seconds) <
                    abs(Double(numerator) / Double(denominator) - seconds) {
                    numerator = boundedNumerator
                    denominator = boundedDenominator
                }
                break
            }
            previousNumerator = numerator
            numerator = Int(nextNumerator)
            previousDenominator = denominator
            denominator = Int(nextDenominator)
            let fractional = remainder - integral
            if fractional < 1e-12 { break }
            remainder = 1 / fractional
        }
        return (UInt16(max(1, min(limit, numerator))), UInt16(max(1, min(limit, denominator))))
    }
}

private extension Array where Element == UInt8 {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }
}

private extension Data {
    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16) |
            (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
}
