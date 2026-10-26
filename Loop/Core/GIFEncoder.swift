import Foundation
import CoreGraphics

/// Writers are confined to the export worker. They never retain earlier images.
protocol AnimationWriter: AnyObject {
    init(destination: URL, size: PixelSize, frameCount: Int, settings: ExportSettings) throws
    func add(_ image: CGImage, delay: Double, gifDelayCentiseconds: Int) throws
    func finish() throws
}

/// A file-backed GIF89a writer with a per-frame adaptive palette and optional
/// serpentine Floyd–Steinberg dithering. The LZW dictionary is bounded at 4096
/// entries and compressed bytes are written in 255-byte GIF sub-blocks.
final class GIFEncoder: AnimationWriter {
    private let output: AnimationOutputFile
    private let size: PixelSize
    private let expectedFrames: Int
    private let paletteSize: Int
    private let dither: Bool
    private var sharedPalette: AdaptiveGIFPalette?
    private var previousIndices: [UInt8]?
    private var addedFrames = 0
    private var finished = false
    private var failed = false

    init(destination: URL, size: PixelSize, frameCount: Int, settings: ExportSettings) throws {
        try EncoderRaster.validate(size: size, frameCount: frameCount)
        guard [64, 128, 256].contains(settings.paletteSize),
              (0...65535).contains(settings.loopCount) else {
            throw LoopError.encoding("The GIF color palette or repeat count is invalid.")
        }
        self.size = size
        expectedFrames = frameCount
        paletteSize = settings.paletteSize
        dither = settings.dither
        output = try AnimationOutputFile(destination: destination)
        do {
            var header = Array("GIF89a".utf8)
            header.appendLittleEndian(UInt16(size.width))
            header.appendLittleEndian(UInt16(size.height))
            // No global color table: every frame owns its adaptive color table.
            header += [0x70, 0x00, 0x00]
            try output.write(header)
            // NETSCAPE's finite value is repeats after the first presentation.
            // Omitting the extension is the interoperable way to play once.
            if settings.loopCount != 1 {
                let repeats = settings.loopCount == 0 ? 0 : settings.loopCount - 1
                var loop: [UInt8] = [0x21, 0xff, 0x0b]
                loop += Array("NETSCAPE2.0".utf8)
                loop += [0x03, 0x01]
                loop.appendLittleEndian(UInt16(repeats))
                loop.append(0x00)
                try output.write(loop)
            }
        } catch {
            try? output.close()
            throw error
        }
    }

    func prepareStablePalette(_ images: [CGImage]) throws {
        guard addedFrames == 0 else { return }
        var pixels=[UInt8]()
        for image in images.prefix(12) {
            pixels += try EncoderRaster.rgba(image, size: PixelSize(width:image.width,height:image.height), opaque:true)
        }
        if !pixels.isEmpty {sharedPalette=AdaptiveGIFPalette(pixels:pixels,maximumColors:paletteSize)}
    }

    func add(_ image: CGImage, delay: Double, gifDelayCentiseconds: Int) throws {
        guard !finished, !failed, addedFrames < expectedFrames else {
            throw LoopError.encoding("The GIF writer cannot accept another frame.")
        }
        do {
            guard (1...65535).contains(gifDelayCentiseconds) else {
                throw LoopError.encoding("The GIF frame duration is outside the format's supported range.")
            }
            try autoreleasepool {
                let pixels = try EncoderRaster.rgba(image, size: size, opaque: true)
                let palette = sharedPalette ?? AdaptiveGIFPalette(pixels: pixels, maximumColors: paletteSize)
                let indices = palette.indices(for: pixels, width: size.width, height: size.height, dither: dither)

                // Retain the previous canvas until this full-frame image replaces it.
                var control: [UInt8] = [0x21, 0xf9, 0x04, 0x04]
                control.appendLittleEndian(UInt16(gifDelayCentiseconds))
                control += [0x00, 0x00]
                try output.write(control)

                let minimumCodeSize = paletteSize == 64 ? 6 : paletteSize == 128 ? 7 : 8
                var x0=0,y0=0,x1=size.width-1,y1=size.height-1
                if sharedPalette != nil, let old=previousIndices, old.count==indices.count {
                    x0=size.width;y0=size.height;x1=0;y1=0
                    for y in 0..<size.height {for x in 0..<size.width where indices[y*size.width+x] != old[y*size.width+x] {
                        x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
                    }}
                    if x0>x1 || y0>y1 {x0=0;x1=0;y0=0;y1=0}
                }
                let patchWidth=x1-x0+1,patchHeight=y1-y0+1
                var encoded=indices
                if patchWidth != size.width || patchHeight != size.height {
                    encoded=[];encoded.reserveCapacity(patchWidth*patchHeight)
                    for y in y0...y1 {encoded.append(contentsOf:indices[(y*size.width+x0)...(y*size.width+x1)])}
                }
                if sharedPalette != nil {previousIndices=indices}
                var descriptor: [UInt8] = [0x2c]
                descriptor.appendLittleEndian(UInt16(x0));descriptor.appendLittleEndian(UInt16(y0))
                descriptor.appendLittleEndian(UInt16(patchWidth))
                descriptor.appendLittleEndian(UInt16(patchHeight))
                descriptor.append(0x80 | UInt8(minimumCodeSize - 1))
                try output.write(descriptor)
                try output.write(palette.tableBytes(paddedTo: paletteSize))
                try output.write([UInt8(minimumCodeSize)])
                try GIFLZW.write(encoded, minimumCodeSize: minimumCodeSize, to: output)
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
            throw LoopError.encoding("The GIF writer has already closed.")
        }
        do {
            guard addedFrames == expectedFrames else {
                throw LoopError.encoding("GIF export stopped before every frame was written.")
            }
            try output.write([0x3b])
            try output.close()
            finished = true
        } catch {
            failed = true
            try? output.close()
            throw error
        }
    }
}

// MARK: - Shared bounded frame / file helpers

final class AnimationOutputFile {
    private var handle: FileHandle?

    init(destination: URL) throws {
        guard destination.isFileURL,
              FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw LoopError.encoding("The export file could not be created. Check the available storage.")
        }
        handle = try FileHandle(forWritingTo: destination)
    }

    func write(_ bytes: [UInt8]) throws { try write(Data(bytes)) }

    func write(_ data: Data) throws {
        guard let handle else { throw LoopError.encoding("The export file is closed.") }
        try handle.write(contentsOf: data)
    }

    func close() throws {
        guard let handle else { return }
        self.handle = nil
        try handle.close()
    }

    deinit { try? handle?.close() }
}

enum EncoderRaster {
    static func validate(size: PixelSize, frameCount: Int) throws {
        guard (1...65535).contains(size.width), (1...65535).contains(size.height),
              frameCount > 0, UInt64(frameCount) <= UInt64(UInt32.max),
              Int64(size.width) * Int64(size.height) <= 67_108_864 else {
            throw LoopError.encoding("The animation dimensions or frame count are unsupported.")
        }
    }

    static func rgba(_ image: CGImage, size: PixelSize, opaque: Bool) throws -> [UInt8] {
        guard image.width == size.width, image.height == size.height else {
            throw LoopError.encoding("An animation frame does not match the export dimensions.")
        }
        var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: size.width, height: size.height,
                                          bitsPerComponent: 8, bytesPerRow: size.width * 4, space: space,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                            CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let rect = CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height))
            if opaque {
                context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
                context.fill(rect)
            }
            context.setBlendMode(opaque ? .normal : .copy)
            context.draw(image, in: rect)
            return true
        }
        guard rendered else { throw LoopError.encoding("A frame rendering buffer could not be allocated.") }
        return pixels
    }

    static func image(_ image: CGImage, size: PixelSize) throws -> CGImage {
        let pixels = try rgba(image, size: size, opaque: false)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let result = CGImage(width: size.width, height: size.height, bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: size.width * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue |
                                    CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false,
                                   intent: .defaultIntent) else {
            throw LoopError.encoding("A PNG frame rendering buffer could not be allocated.")
        }
        return result
    }
}

private extension Array where Element == UInt8 {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}

// MARK: - Adaptive weighted median-cut palette

private struct GIFColor {
    var r: Int
    var g: Int
    var b: Int
    var count: Int
}

private struct GIFColorBox {
    var colors: [GIFColor]
    var population: Int
    var channel: Int
    var score: Double

    init(_ colors: [GIFColor]) {
        self.colors = colors
        var rLow = 255, gLow = 255, bLow = 255
        var rHigh = 0, gHigh = 0, bHigh = 0
        var population = 0
        for color in colors {
            population += color.count
            rLow = min(rLow, color.r); rHigh = max(rHigh, color.r)
            gLow = min(gLow, color.g); gHigh = max(gHigh, color.g)
            bLow = min(bLow, color.b); bHigh = max(bHigh, color.b)
        }
        self.population = population
        let ranges = [rHigh - rLow, gHigh - gLow, bHigh - bLow]
        channel = ranges[1] > ranges[0] ? 1 : 0
        if ranges[2] > ranges[channel] { channel = 2 }
        score = colors.count > 1 ? Double(ranges[channel]) * sqrt(Double(population)) : 0
    }

    var average: GIFColor {
        var r = 0, g = 0, b = 0
        for color in colors {
            r += color.r * color.count
            g += color.g * color.count
            b += color.b * color.count
        }
        let divisor = max(1, population)
        return GIFColor(r: (r + divisor / 2) / divisor, g: (g + divisor / 2) / divisor,
                        b: (b + divisor / 2) / divisor, count: population)
    }

    func split() -> (GIFColorBox, GIFColorBox) {
        let channel = self.channel
        let sorted = colors.sorted { a, b in
            let av = channel == 0 ? a.r : channel == 1 ? a.g : a.b
            let bv = channel == 0 ? b.r : channel == 1 ? b.g : b.b
            if av != bv { return av < bv }
            if a.r != b.r { return a.r < b.r }
            if a.g != b.g { return a.g < b.g }
            return a.b < b.b
        }
        var cumulative = 0
        var division = 1
        for index in 0..<(sorted.count - 1) {
            cumulative += sorted[index].count
            division = index + 1
            if cumulative >= population / 2 { break }
        }
        return (GIFColorBox(Array(sorted[..<division])), GIFColorBox(Array(sorted[division...])))
    }
}

private struct AdaptiveGIFPalette {
    var colors: [GIFColor]

    init(pixels: [UInt8], maximumColors: Int) {
        // A fixed 5-bit RGB histogram bounds quantizer memory regardless of image size.
        var counts = [Int](repeating: 0, count: 32768)
        var red = [Int](repeating: 0, count: 32768)
        var green = [Int](repeating: 0, count: 32768)
        var blue = [Int](repeating: 0, count: 32768)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
            let key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
            counts[key] += 1
            red[key] += r; green[key] += g; blue[key] += b
        }
        var samples: [GIFColor] = []
        samples.reserveCapacity(32768)
        for index in 0..<32768 where counts[index] != 0 {
            let n = counts[index]
            samples.append(GIFColor(r: (red[index] + n / 2) / n,
                                    g: (green[index] + n / 2) / n,
                                    b: (blue[index] + n / 2) / n, count: n))
        }
        if samples.count <= maximumColors {
            colors = samples
        } else {
            var boxes = [GIFColorBox(samples)]
            while boxes.count < maximumColors {
                guard let index = boxes.indices.max(by: { boxes[$0].score < boxes[$1].score }),
                      boxes[index].score > 0 else { break }
                let (left, right) = boxes[index].split()
                boxes[index] = left
                boxes.append(right)
            }
            colors = boxes.map(\.average)
        }
        if colors.isEmpty { colors = [GIFColor(r: 0, g: 0, b: 0, count: 1)] }
    }

    func tableBytes(paddedTo count: Int) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(count * 3)
        for index in 0..<count {
            let color = colors[min(index, colors.count - 1)]
            result += [UInt8(color.r), UInt8(color.g), UInt8(color.b)]
        }
        return result
    }

    func indices(for pixels: [UInt8], width: Int, height: Int, dither: Bool) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height)
        var lookup = [Int16](repeating: -1, count: 32768)
        func nearest(_ r: Int, _ g: Int, _ b: Int) -> Int {
            let key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
            if lookup[key] >= 0 { return Int(lookup[key]) }
            // Use bin centers so lookup results do not depend on traversal order.
            let red = ((key >> 10) & 31) * 8 + 4
            let green = ((key >> 5) & 31) * 8 + 4
            let blue = (key & 31) * 8 + 4
            var best = 0, bestDistance = Int.max
            for index in colors.indices {
                let color = colors[index]
                let dr = color.r - red, dg = color.g - green, db = color.b - blue
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance { bestDistance = distance; best = index }
            }
            lookup[key] = Int16(best)
            return best
        }
        if !dither {
            for index in result.indices {
                let offset = index * 4
                result[index] = UInt8(nearest(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2])))
            }
            return result
        }
        var current = [Float](repeating: 0, count: (width + 2) * 3)
        var next = current
        for y in 0..<height {
            let direction = y.isMultiple(of: 2) ? 1 : -1
            var x = direction == 1 ? 0 : width - 1
            for _ in 0..<width {
                let pixel = (y * width + x) * 4
                let errorOffset = (x + 1) * 3
                let r = min(255, max(0, Float(pixels[pixel]) + current[errorOffset]))
                let g = min(255, max(0, Float(pixels[pixel + 1]) + current[errorOffset + 1]))
                let b = min(255, max(0, Float(pixels[pixel + 2]) + current[errorOffset + 2]))
                let index = nearest(Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
                result[y * width + x] = UInt8(index)
                let color = colors[index]
                for c in 0..<3 {
                    let error = c == 0 ? r - Float(color.r) : c == 1 ? g - Float(color.g) : b - Float(color.b)
                    current[errorOffset + direction * 3 + c] += error * (7.0 / 16.0)
                    next[errorOffset - direction * 3 + c] += error * (3.0 / 16.0)
                    next[errorOffset + c] += error * (5.0 / 16.0)
                    next[errorOffset + direction * 3 + c] += error * (1.0 / 16.0)
                }
                x += direction
            }
            swap(&current, &next)
            for index in next.indices { next[index] = 0 }
        }
        return result
    }
}

// MARK: - GIF LZW (late code-width change)

private enum GIFLZW {
    static func write(_ indices: [UInt8], minimumCodeSize: Int, to output: AnimationOutputFile) throws {
        guard let first = indices.first else { throw LoopError.encoding("An empty GIF frame cannot be written.") }
        let clearCode = 1 << minimumCodeSize
        let endCode = clearCode + 1
        var nextCode = endCode + 1
        var codeWidth = minimumCodeSize + 1
        var dictionary: [UInt32: Int] = [:]
        dictionary.reserveCapacity(4096)
        var pendingBits: UInt32 = 0
        var pendingCount = 0
        var block: [UInt8] = []
        block.reserveCapacity(255)

        func appendByte(_ byte: UInt8) throws {
            block.append(byte)
            if block.count == 255 {
                try output.write([255])
                try output.write(block)
                block.removeAll(keepingCapacity: true)
            }
        }
        func writeCode(_ code: Int) throws {
            pendingBits |= UInt32(code) << pendingCount
            pendingCount += codeWidth
            while pendingCount >= 8 {
                try appendByte(UInt8(truncatingIfNeeded: pendingBits))
                pendingBits >>= 8
                pendingCount -= 8
            }
        }
        func writeDataCode(_ code: Int) throws {
            try writeCode(code)
            // The encoder's dictionary is one entry ahead of the decoder. Grow
            // only after emitting the code that lets the decoder catch up.
            if nextCode == (1 << codeWidth), codeWidth < 12 { codeWidth += 1 }
        }

        try writeCode(clearCode)
        var prefix = Int(first)
        for suffix in indices.dropFirst() {
            let key = (UInt32(prefix) << 8) | UInt32(suffix)
            if let code = dictionary[key] {
                prefix = code
            } else {
                try writeDataCode(prefix)
                if nextCode < 4096 {
                    dictionary[key] = nextCode
                    nextCode += 1
                } else {
                    try writeCode(clearCode)
                    dictionary.removeAll(keepingCapacity: true)
                    nextCode = endCode + 1
                    codeWidth = minimumCodeSize + 1
                }
                prefix = Int(suffix)
            }
        }
        try writeDataCode(prefix)
        try writeCode(endCode)
        if pendingCount > 0 { try appendByte(UInt8(truncatingIfNeeded: pendingBits)) }
        if !block.isEmpty {
            try output.write([UInt8(block.count)])
            try output.write(block)
        }
        try output.write([0x00])
    }
}
