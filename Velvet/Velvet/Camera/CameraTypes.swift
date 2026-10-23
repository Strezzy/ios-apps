import AVFoundation
import Foundation

enum PhotoFormat: String, CaseIterable, Identifiable {
    case heif, jpeg, raw
    var id: String { rawValue }
    var label: String { self == .raw ? "RAW + JPEG" : rawValue.uppercased() }
}

enum CameraFlash: String, CaseIterable, Identifiable {
    case off, auto, on
    var id: String { rawValue }
    var avMode: AVCaptureDevice.FlashMode {
        switch self { case .off: return .off; case .auto: return .auto; case .on: return .on }
    }
}

struct CameraLens: Identifiable, Equatable {
    let id: String
    let label: String
    let isFront: Bool
}

struct VideoMode: Identifiable, Hashable {
    let width: Int
    let height: Int
    let fps: Int
    let codec: String
    var id: String { "\(width)x\(height)-\(fps)-\(codec)" }
    var label: String { "\(height == 2160 ? "4K" : "\(height)p") · \(fps) · \(codec == "hevc" ? "HEVC" : "H.264")" }
    static let standard = VideoMode(width: 1920, height: 1080, fps: 30, codec: "h264")
    var codecType: AVVideoCodecType { codec == "hevc" ? .hevc : .h264 }
    var outputSettings: [String: Any] {
        [AVVideoCodecKey: codecType, AVVideoWidthKey: width, AVVideoHeightKey: height,
         AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: min(60_000_000, max(5_000_000, width * height * fps / 5)),
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0
         ]]
    }
}

enum CameraError: LocalizedError {
    case permission, unavailable, unsupported, recordingFailed, noSamples, interrupted, invalidRange
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow camera access in iPhone Settings to take photographs."
        case .unavailable: return "The camera is unavailable. Close other camera apps and try again."
        case .unsupported: return "This capture combination is unavailable on the active camera."
        case .recordingFailed: return "Recording could not be saved securely. The incomplete recording was discarded."
        case .noSamples: return "No video frames were captured. Try recording again."
        case .interrupted: return "Camera capture was interrupted. Any incomplete recording was discarded."
        case .invalidRange: return "The encrypted movie could not be read."
        }
    }
}

struct CapturedPhoto {
    let data: Data
    let fileExtension: String
    let width: Int
    let height: Int
}

struct CameraCapabilities {
    let lenses: [CameraLens]
    let selectedLens: String
    let modes: [VideoMode]
    let supportsRAW: Bool
    let supportsHEIF: Bool
    let resolution: String
    let minimumExposureBias: Float
    let maximumExposureBias: Float
}

struct CameraManualCapabilities: Equatable {
    let supportsExposure: Bool
    let minimumISO: Float
    let maximumISO: Float
    let minimumShutterSeconds: Double
    let maximumShutterSeconds: Double
    let currentISO: Float
    let currentShutterSeconds: Double
    let exposureIsManual: Bool
    let supportsWhiteBalance: Bool
    let maximumWhiteBalanceGain: Float
    let redGain: Float
    let greenGain: Float
    let blueGain: Float
    let whiteBalanceIsLocked: Bool
}
