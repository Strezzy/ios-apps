import Foundation
import Speech
import AVFoundation

/// SpeechTranscriber is an Apple on-device module. No SFSpeechRecognizer or
/// network-recognition fallback is installed. Language downloads are explicit.
actor LocalSpeechService {
    private var analyzer: SpeechAnalyzer?
    private var recognitionID = UUID()

    func languages() async -> [String] {
        guard SpeechTranscriber.isAvailable else { return [] }
        return await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
    }
    func state(language: String) async -> SpeechAssetState {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { return .unsupported }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: { $0.identifier == locale.identifier }) ? .ready : .needsDownload
    }
    func install(language: String) async throws {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw RiftFailure("Apple's on-device speech model is not supported for this language or device. Text chat is still available.")
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        // This is the only voice-mode operation permitted to request a download.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }
    func cancel() async {
        recognitionID = UUID()
        let active = analyzer; analyzer = nil
        await active?.cancelAndFinishNow()
    }
    func transcribe(file: URL, language: String) async throws -> String {
        guard await state(language: language) == .ready,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw RiftFailure("Download the selected speech language before starting voice chat. Audio is never sent to a server.")
        }
        try Task.checkCancellation()
        let id = UUID(); recognitionID = id
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let session = SpeechAnalyzer(modules: [module]); analyzer = session
        let results = Task<String, Error> {
            var text = ""
            for try await result in module.results {
                try Task.checkCancellation()
                text += String(result.text.characters)
                guard text.utf8.count < 100_000 else { throw RiftFailure("This voice turn is too long.") }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            let audio = try AVAudioFile(forReading: file)
            if let last = try await session.analyzeSequence(from: audio) {
                try await session.finalizeAndFinish(through: last)
            } else { await session.cancelAndFinishNow() }
            let text = try await results.value
            try Task.checkCancellation()
            guard recognitionID == id else { throw CancellationError() }
            analyzer = nil
            return text
        } catch {
            results.cancel()
            await session.cancelAndFinishNow()
            if recognitionID == id { analyzer = nil }
            throw error
        }
    }
}
