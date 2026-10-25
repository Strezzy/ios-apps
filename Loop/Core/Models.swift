import Foundation
import CoreGraphics

struct PixelSize: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var aspect: Double { Double(max(1, width)) / Double(max(1, height)) }
    var longEdge: Int { max(width, height) }
    var label: String { "\(width) × \(height)" }
}

struct VideoMetadata: Codable, Equatable, Sendable {
    var name: String
    var duration: Double
    var size: PixelSize
    var nominalFrameRate: Double
    var isHDR: Bool
    var byteCount: Int64
}

/// Every editing coordinate is in the upright source image, with the origin at its top left.
struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    static let centered = NormalizedRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
    func clamped() -> NormalizedRect {
        let w = min(1, max(0.005, width.isFinite ? width : 0.3))
        let h = min(1, max(0.005, height.isFinite ? height : 0.3))
        return NormalizedRect(x: min(1 - w, max(0, x.isFinite ? x : 0)),
                              y: min(1 - h, max(0, y.isFinite ? y : 0)), width: w, height: h)
    }
    static func interpolate(_ a: Self, _ b: Self, fraction: Double) -> Self {
        let f = min(1, max(0, fraction))
        return Self(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f,
                    width: a.width + (b.width - a.width) * f,
                    height: a.height + (b.height - a.height) * f).clamped()
    }
}

enum CropAspect: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, portrait, portraitFourFive, square, landscape, landscapeFourThree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .portrait: return "Portrait 9:16"
        case .portraitFourFive: return "Portrait 4:5"
        case .square: return "Square 1:1"
        case .landscape: return "Landscape 16:9"
        case .landscapeFourThree: return "Landscape 4:3"
        }
    }
    var symbol: String {
        switch self {
        case .portrait, .portraitFourFive: return "rectangle.portrait"
        case .square: return "square"
        default: return "rectangle"
        }
    }
    func ratio(source: PixelSize) -> Double {
        switch self {
        case .original: return source.aspect
        case .portrait: return 9.0 / 16
        case .portraitFourFive: return 4.0 / 5
        case .square: return 1
        case .landscape: return 16.0 / 9
        case .landscapeFourThree: return 4.0 / 3
        }
    }
}

struct CropSettings: Codable, Equatable, Sendable {
    var aspect: CropAspect = .original
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var zoom: Double = 1
    var mirror: Bool = false
    /// Optional so projects saved before subject-follow framing still decode unchanged.
    var tracking: CropTrackingSettings?
    func rect(source: PixelSize) -> NormalizedRect {
        let target = aspect.ratio(source: source)
        let z = min(8, max(1, zoom.isFinite ? zoom : 1))
        let width = min(1, target / source.aspect) / z
        let height = min(1, source.aspect / target) / z
        return NormalizedRect(x: centerX - width / 2, y: centerY - height / 2,
                              width: width, height: height).clamped()
    }
}

enum AnimationFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case gif, apng
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { self == .gif ? "gif" : "png" }
}

enum PlaybackMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case forward, reverse, bounce
    var id: String { rawValue }
    var title: String { self == .bounce ? "Ping-pong" : rawValue.capitalized }
    var symbol: String { self == .forward ? "play" : self == .reverse ? "backward" : "arrow.left.arrow.right" }
}

struct ExportSettings: Codable, Equatable, Sendable {
    var format: AnimationFormat = .gif
    var frameRate: Double = 24
    /// Zero uses the crop's native resolution, bounded by the documented 4096-pixel limit.
    var maximumDimension: Int = 1080
    var allowUpscaling: Bool = false
    var speed: Double = 1
    var playback: PlaybackMode = .forward
    /// Zero means forever; positive values mean a total number of plays.
    var loopCount: Int = 0
    var paletteSize: Int = 256
    var dither: Bool = true
}

enum OverlayKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case blur, pixelate, cover, emoji, text
    var id: String { rawValue }
    var title: String { self == .cover ? "Solid cover" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3.fill"
        case .cover: return "rectangle.fill"
        case .emoji: return "face.smiling"
        case .text: return "textformat"
        }
    }
    var isRedaction: Bool { self == .blur || self == .pixelate || self == .cover }
}

enum OverlayShape: String, CaseIterable, Codable, Identifiable, Sendable {
    case ellipse, rectangle
    var id: String { rawValue }
    var title: String { self == .ellipse ? "Circle / oval" : "Rectangle" }
}

struct TrackingKeyframe: Codable, Equatable, Sendable {
    var time: Double
    var rect: NormalizedRect
    var confidence: Double = 1
    var manual: Bool = false
}

struct OverlayItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: OverlayKind
    var shape: OverlayShape = .ellipse
    var rect: NormalizedRect = .centered
    var content: String = "😎"
    var strength: Double = 0.7
    var opacity: Double = 1
    var startTime: Double
    var endTime: Double
    var trackingEnabled: Bool = false
    var keyframes: [TrackingKeyframe] = []
    var trackingNeedsReview: Bool = false
    var title: String { kind == .emoji || kind == .text ? content : kind.title }
    func isActive(at time: Double) -> Bool { time >= startTime - 0.0001 && time <= endTime + 0.0001 }
    func rect(at time: Double) -> NormalizedRect {
        guard !keyframes.isEmpty else { return rect.clamped() }
        // Tracking, loading and manual edits maintain timestamp order. Do not sort/copy
        // thousands of tracking samples for every rendered frame.
        let keys = keyframes
        if time <= keys[0].time { return keys[0].rect.clamped() }
        if time >= keys[keys.count - 1].time { return keys[keys.count - 1].rect.clamped() }
        var low = 0, high = keys.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if keys[middle].time <= time { low = middle } else { high = middle }
        }
        let span = keys[high].time - keys[low].time
        return .interpolate(keys[low].rect, keys[high].rect,
                            fraction: span > 0 ? (time - keys[low].time) / span : 0)
    }
    mutating func setKeyframe(at time: Double, rect: NormalizedRect) {
        keyframes.removeAll { abs($0.time - time) < 0.005 }
        keyframes.append(TrackingKeyframe(time: time, rect: rect.clamped(), manual: true))
        keyframes.sort { $0.time < $1.time }
    }
}

struct ColorAdjustments: Codable, Equatable, Sendable {
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
}

struct LoopProject: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sourceFilename: String
    var metadata: VideoMetadata
    var createdAt = Date()
    var modifiedAt = Date()
    var trimStart: Double = 0
    var trimEnd: Double
    var crop = CropSettings()
    var export = ExportSettings()
    var overlays: [OverlayItem] = []
    var adjustments = ColorAdjustments()
    init(name: String, sourceFilename: String, metadata: VideoMetadata) {
        self.name = name
        self.sourceFilename = sourceFilename
        self.metadata = metadata
        self.trimEnd = min(metadata.duration, 6)
    }
    var duration: Double { max(0, trimEnd - trimStart) }
}

struct ExportProgress: Sendable {
    var fraction: Double
    var completedFrames: Int
    var totalFrames: Int
    var message: String
}

struct ExportResult: Sendable {
    var url: URL
    var size: PixelSize
    var frameCount: Int
    var duration: Double
    var byteCount: Int64
}

struct SavedExport: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var filename: String
    var createdAt = Date()
    var format: AnimationFormat
    var size: PixelSize
    var frameCount: Int
    var duration: Double
    var byteCount: Int64
    var thumbnailFilename: String?
}

enum LoopError: LocalizedError {
    case invalidVideo(String)
    case invalidSettings(String)
    case encoding(String)
    case trackingLost(time: Double)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .invalidVideo(let detail), .invalidSettings(let detail), .encoding(let detail): return detail
        case .trackingLost(let time): return String(format: "Tracking lost its subject at %.2f s. Adjust the selection or add position keyframes, then review the whole clip before exporting.", time)
        case .cancelled: return "The operation was cancelled."
        }
    }
}
