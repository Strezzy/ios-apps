import Foundation
import CoreGraphics

enum MediaKind: String, Codable, Sendable { case photo, video }

struct PixelSize: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var label: String { "\(width) × \(height)" }
}

enum OutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case spatial, sideBySide, overUnder, anaglyph, separateEyes, depthMap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spatial: "Apple Spatial"
        case .sideBySide: "Full Side-by-Side"
        case .overUnder: "Full Over-Under"
        case .anaglyph: "Red / Cyan"
        case .separateEyes: "Separate Eyes"
        case .depthMap: "Depth Map"
        }
    }
    var symbol: String {
        switch self {
        case .spatial: "vision.pro"
        case .sideBySide: "rectangle.split.2x1"
        case .overUnder: "rectangle.split.1x2"
        case .anaglyph: "eyeglasses"
        case .separateEyes: "square.on.square"
        case .depthMap: "square.3.layers.3d"
        }
    }
    var detail: String {
        switch self {
        case .spatial: "Spatial HEIC photos or multiview HEVC video."
        case .sideBySide: "Full source resolution for each eye, side by side."
        case .overUnder: "Full source resolution for each eye, stacked vertically."
        case .anaglyph: "View with red / cyan 3D glasses."
        case .separateEyes: "Two full-resolution files, one for each eye."
        case .depthMap: "Export the estimated depth at source dimensions."
        }
    }
    func outputSize(for source: PixelSize) -> PixelSize {
        switch self {
        case .sideBySide: PixelSize(width: source.width * 2, height: source.height)
        case .overUnder: PixelSize(width: source.width, height: source.height * 2)
        default: source
        }
    }
}

enum PhotoEncoding: String, CaseIterable, Codable, Identifiable, Sendable {
    case heic, jpeg, png
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum DepthModelChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case balanced, detailed
    var id: String { rawValue }
    var title: String { self == .balanced ? "Balanced" : "Detailed" }
}

struct ConversionOptions: Codable, Equatable, Sendable {
    var format: OutputFormat = .sideBySide
    var photoEncoding: PhotoEncoding = .heic
    var model: DepthModelChoice = .detailed
    /// Maximum total left-to-right disparity as a fraction of source width.
    var depthAmount: Double = 0.018
    /// Normalized inverse depth placed on the screen plane.
    var convergence: Double = 0.5
    var swapEyes = false
    var memorySaver = true
    var temporalStability = true
    var preserveAudio = true
    /// Metadata for a synthetic rectilinear virtual camera, never a capture claim.
    var horizontalFieldOfViewDegrees: Double = 65
    var virtualBaselineMillimeters: Double = 64
}

struct MediaSource: Identifiable, Codable, Sendable {
    var id = UUID()
    var url: URL
    var name: String
    var kind: MediaKind
    var size: PixelSize
    var frameRate: Double = 0
    var duration: Double = 0
    var hasAudio = false
    var isHDR = false
    var summary: String {
        kind == .photo ? size.label : "\(size.label) · \(frameRate.formatted(.number.precision(.fractionLength(0...3)))) fps"
    }
}

struct ConversionProgress: Sendable {
    var fraction: Double
    var stage: String
    var framesProcessed: Int = 0
    var totalFramesEstimate: Int = 0
}

struct ExportResult: Identifiable, Codable, Sendable {
    var id = UUID()
    var files: [URL]
    var createdAt = Date()
    var sourceName: String
    var format: OutputFormat
    var size: PixelSize
    var frameCount: Int = 0
    var frameRate: Double = 0
    var duration: Double = 0
    var note: String = ""
}

struct DepthMap: Sendable {
    var width: Int
    var height: Int
    /// Row-major inverse depth: 0 far, 1 near, finite values only.
    var values: [Float]
}

enum DepthCheckError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

enum AppPaths {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static func directory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func exportDirectory() throws -> URL {
        let url = try directory("Exports").appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
