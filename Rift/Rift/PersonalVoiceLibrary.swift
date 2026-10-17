import Foundation
import AVFoundation

struct PersonalVoice: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let created: Date
}

/// Names never become paths. Only locally generated, bounded voice profiles are loaded.
struct PersonalVoiceLibrary: Sendable {
    let root: URL
    static var applicationRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RiftPersonalVoices", isDirectory: true)
    }
    init(root: URL = Self.applicationRoot) { self.root = root }
    func entries() throws -> [PersonalVoice] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { url in
                guard let voice = try? JSONDecoder().decode(PersonalVoice.self, from: Data(contentsOf: url)),
                      url.deletingPathExtension().lastPathComponent == voice.id.uuidString,
                      FileManager.default.fileExists(atPath: profileURL(voice.id).path) else { return nil }
                return voice
            }.sorted { $0.created < $1.created }
    }
    func profileURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".bin") }
    func save(profile: Data, name: String) throws -> PersonalVoice {
        // Pocket's English conditioning is at most 125 frames × 1024 Float32s.
        guard !profile.isEmpty, profile.count <= 125 * 1024 * 4, profile.count % (1024 * 4) == 0 else {
            throw RiftFailure("This personal voice profile is invalid.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let voice = PersonalVoice(id: UUID(), name: clean.isEmpty ? "My Voice" : clean, created: Date())
        let dataURL = profileURL(voice.id)
        do {
            try profile.write(to: dataURL, options: [.atomic, .completeFileProtection])
            try JSONEncoder().encode(voice).write(to: root.appendingPathComponent(voice.id.uuidString + ".json"), options: [.atomic, .completeFileProtection])
        } catch { try? FileManager.default.removeItem(at: dataURL); throw error }
        var directory = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return voice
    }
    func delete(_ voice: PersonalVoice) throws {
        try FileManager.default.removeItem(at: profileURL(voice.id))
        try FileManager.default.removeItem(at: root.appendingPathComponent(voice.id.uuidString + ".json"))
    }
    /// Bound decoding before the library's encoder sees the file. Never upload the recording.
    static func validateRecording(_ url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20_000_000 else { throw RiftFailure("Choose an audio clip smaller than 20 MB.") }
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration >= 3, duration <= 10.1,
              file.processingFormat.channelCount <= 2 else {
            throw RiftFailure("Choose 3–10 seconds of clear speech in a mono or stereo audio file. Five to ten seconds works best.")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw RiftFailure("This recording could not be read.")
        }
        try file.read(into: buffer)
        guard let samples = buffer.floatChannelData, buffer.frameLength > 0 else { throw RiftFailure("Use a WAV, M4A, or MP3 speech recording.") }
        var power: Double = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for i in 0..<Int(buffer.frameLength) {
                let x = Double(samples[channel][i]); guard x.isFinite else { throw RiftFailure("The recording contains invalid audio.") }
                power += x * x
            }
        }
        guard power / Double(Int(buffer.frameLength) * Int(buffer.format.channelCount)) > 0.000001 else {
            throw RiftFailure("This clip is too quiet. Choose a clear recording of your voice.")
        }
    }
}
