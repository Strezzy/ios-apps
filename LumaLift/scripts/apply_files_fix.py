#!/usr/bin/env python3
"""Apply the narrow Lucid Files-import repair without changing its media engine."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POLICY = '''import UniformTypeIdentifiers

/// File providers may advertise a playable movie as generic data. Let the user
/// select the file, then use ClipInfo.inspect to validate its actual video track.
/// This does not add codecs or relax the existing SDR/resolution restrictions.
enum VideoFileImportPolicy {
    static let allowedContentTypes: [UTType] = [.item]
}
'''
OLD_COPY = '''    static func importMovie(_ source: URL) throws -> URL {
        guard source.isFileURL else { throw LiftError.message("Only local video files can be imported.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let folder = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try prepare(folder)
        let result = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: result)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: result.path)
            return result
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
'''
NEW_COPY = '''    static func importMovie(_ source: URL) throws -> URL {
        guard source.isFileURL else { throw LiftError.message("Only local video files can be imported.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // Coordinate while permission is held so Files providers can supply a
        // stable local file. The Files path calls this on a background task.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var copied: Result<URL, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            copied = Result {
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                guard values.isRegularFile == true, values.isDirectory != true else {
                    throw LiftError.message("Choose a video file, not a folder.")
                }
                let folder = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
                do {
                    try prepare(folder)
                    let result = folder.appendingPathComponent(source.lastPathComponent)
                    try FileManager.default.copyItem(at: readable, to: result)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: result.path)
                    return result
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let copied else {
            throw LiftError.message("Files could not provide this video. Make sure it is downloaded and available on your device, then try again.")
        }
        return try copied.get()
    }
'''
TEST_NAMES = [
    'testFilesPickerAcceptsGenericProviderTypes',
    'testFilesImportPreservesOriginalMovieAndReadsGenericFiles',
    'testFilesImportAcceptsMP4AndKeepsSettings',
    'testFilesImportRejectsNonVideoWithoutReplacingClip',
    'testFilesImportRejectsDirectoriesAndMissingFiles',
    'testLucidFilesFixKeepsExistingBundleIdentity',
]
TEST_INSERT = '''    func testFilesPickerAcceptsGenericProviderTypes() {
        let allowed = VideoFileImportPolicy.allowedContentTypes
        XCTAssertEqual(allowed, [.item])
        let generic = UTType(importedAs: "com.billy.lucid.tests.provider-data", conformingTo: .data)
        for type in [UTType.movie, .video, .mpeg4Movie, .quickTimeMovie, .data, generic] {
            XCTAssertTrue(allowed.contains { type.conforms(to: $0) }, "Files must allow \\(type.identifier)")
        }
        XCTAssertFalse([UTType.movie, .video].contains { UTType.data.conforms(to: $0) },
                       "The old movie-only filter excluded generic provider data.")
    }
    func testFilesImportPreservesOriginalMovieAndReadsGenericFiles() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let fixture = try await makeVideo(at: root.appendingPathComponent("fixture.mov"))
        let original = try Data(contentsOf: fixture)
        for name in ["Movie.MOV", "provider-video.bin", "provider-video"] {
            let source = root.appendingPathComponent(name)
            try fm.copyItem(at: fixture, to: source)
            let imported = try LocalFiles.importMovie(source)
            defer { try? fm.removeItem(at: imported.deletingLastPathComponent()) }
            XCTAssertNotEqual(imported, source)
            XCTAssertEqual(try Data(contentsOf: imported), original)
            XCTAssertEqual(try Data(contentsOf: source), original)
            let clip = try await ClipInfo.inspect(imported)
            XCTAssertEqual(clip.width, 64)
            XCTAssertEqual(clip.height, 48)
            XCTAssertGreaterThan(clip.duration, 0)
        }
    }
    @MainActor func testFilesImportAcceptsMP4AndKeepsSettings() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let movie = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let mp4 = root.appendingPathComponent("Files video.mp4")
        let session = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: movie), presetName: AVAssetExportPresetPassthrough))
        try await session.export(to: mp4, as: .mp4)
        let original = try Data(contentsOf: mp4)
        let store = AppStore()
        store.settings.fps = 60
        store.settings.strength = 0.42
        let settings = store.settings
        let library = store.library.map(\\.id)
        await store.importFile(mp4)
        let clip = try XCTUnwrap(store.clip)
        defer { try? fm.removeItem(at: clip.url.deletingLastPathComponent()) }
        XCTAssertNil(store.error)
        XCTAssertFalse(store.importing)
        XCTAssertNotEqual(clip.url, mp4)
        XCTAssertEqual(store.settings, settings)
        XCTAssertEqual(store.library.map(\\.id), library)
        XCTAssertEqual(try Data(contentsOf: clip.url), original)
        XCTAssertEqual(try Data(contentsOf: mp4), original)
    }
    @MainActor func testFilesImportRejectsNonVideoWithoutReplacingClip() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let store = AppStore()
        await store.importFile(source)
        let clip = try XCTUnwrap(store.clip)
        defer { try? fm.removeItem(at: clip.url.deletingLastPathComponent()) }
        let importsBefore = Set(try fm.contentsOfDirectory(atPath: LocalFiles.imports.path))
        for name in ["not-a-video.txt", "not-a-video.mov"] {
            let invalid = root.appendingPathComponent(name)
            let data = Data("This is a text file, not a video.".utf8)
            try data.write(to: invalid)
            store.error = nil
            await store.importFile(invalid)
            XCTAssertNotNil(store.error)
            XCTAssertFalse(store.importing)
            XCTAssertEqual(store.clip?.url, clip.url)
            XCTAssertTrue(fm.fileExists(atPath: clip.url.path))
            XCTAssertEqual(try Data(contentsOf: invalid), data)
            XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: LocalFiles.imports.path)), importsBefore)
        }
    }
    func testFilesImportRejectsDirectoriesAndMissingFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try LocalFiles.prepare(LocalFiles.imports)
        let before = Set(try fm.contentsOfDirectory(atPath: LocalFiles.imports.path))
        XCTAssertThrowsError(try LocalFiles.importMovie(root))
        XCTAssertThrowsError(try LocalFiles.importMovie(root.appendingPathComponent("missing.mov")))
        XCTAssertTrue(fm.fileExists(atPath: root.path))
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: LocalFiles.imports.path)), before)
    }
    func testLucidFilesFixKeepsExistingBundleIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.billy.lucid")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Lucid")
    }
'''

def main():
    edits = {}
    def replace(relative, before, after):
        path = ROOT / relative
        text = edits.get(path, path.read_text())
        if after in text:
            return
        if text.count(before) != 1:
            raise RuntimeError(f'Expected one patch location in {relative}; refusing to overwrite unexpected source.')
        edits[path] = text.replace(before, after, 1)
    replace('App/LumaLiftApp.swift', 'allowedContentTypes: [.movie, .video]',
            'allowedContentTypes: VideoFileImportPolicy.allowedContentTypes')
    replace('App/AppStore.swift', OLD_COPY, NEW_COPY)
    for declaration in ['func importPhoto(_ item: PhotosPickerItem) async {', 'func importFile(_ source: URL) async {']:
        replace('App/AppStore.swift', declaration + '\n        guard !working else { return }',
                declaration + '\n        guard !working, !importing else { return }')
    replace('Tests/LumaLiftTests.swift', 'import CoreImage\n', 'import CoreImage\nimport UniformTypeIdentifiers\n')
    replace('Tests/LumaLiftTests.swift', 'final class LumaLiftTests: XCTestCase {\n',
            'final class LumaLiftTests: XCTestCase {\n' + TEST_INSERT)
    replace('scripts/build_ios.py', "DEVICE_TESTS = ['testBundledRIFERunsOnAppleRuntime'",
            'TESTS += ' + repr(TEST_NAMES) + "\nDEVICE_TESTS = ['testBundledRIFERunsOnAppleRuntime'")
    policy_path = ROOT / 'App/VideoFileImportPolicy.swift'
    if policy_path.exists() and policy_path.read_text() != POLICY:
        raise RuntimeError('Unexpected existing import policy; refusing to overwrite it.')
    edits[policy_path] = POLICY
    for path, text in edits.items():
        path.write_text(text)
    print('Applied Lucid Files-import fix and six required regression checks.')

if __name__ == '__main__':
    main()
