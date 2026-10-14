#!/usr/bin/env python3
"""Finish the Files repair using the native regression findings."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TEST_NAMES = [
    'testFilesPickerAcceptsGenericProviderTypes',
    'testFilesImportPreservesOriginalMovieAndReadsGenericFiles',
    'testFilesImportAcceptsMP4AndKeepsSettings',
    'testFilesImportRejectsNonVideoWithoutReplacingClip',
    'testFilesImportRejectsDirectoriesAndMissingFiles',
    'testLucidFilesFixKeepsExistingBundleIdentity',
]
POLICY = '''import Foundation
import UniformTypeIdentifiers

/// File providers may advertise a playable movie as generic data. Let the user
/// select the file, then use ClipInfo.inspect to validate its actual video track.
/// This does not add codecs or relax the existing SDR/resolution restrictions.
enum VideoFileImportPolicy {
    static let allowedContentTypes: [UTType] = [.item]

    /// AVFoundation can reject an otherwise valid MOV/MP4 when its name has an
    /// unknown extension. Give only the private copy a matching container hint.
    /// A recognizable header is not validation: ClipInfo.inspect still decides
    /// whether the file contains a supported, unprotected video track.
    static func stagingFilename(for source: URL, originalName: String) throws -> String {
        let ext = (originalName as NSString).pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { return originalName }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        guard header.count >= 12 else { return originalName }
        let atom = String(data: header.subdata(in: 4..<8), encoding: .ascii)
        let suffix: String
        if atom == "ftyp" {
            let brand = String(data: header.subdata(in: 8..<12), encoding: .ascii)
            suffix = brand == "qt  " ? "mov" : "mp4"
        } else if ["moov", "mdat", "wide", "free", "skip"].contains(atom ?? "") {
            suffix = "mov"
        } else {
            return originalName
        }
        return originalName + "." + suffix
    }
}
'''
EXTRA_MP4 = '''        let opaque = root.appendingPathComponent("provider-movie.data")
        try fm.copyItem(at: mp4, to: opaque)
        await store.importFile(opaque)
        let opaqueClip = try XCTUnwrap(store.clip)
        defer { try? fm.removeItem(at: opaqueClip.url.deletingLastPathComponent()) }
        XCTAssertNil(store.error)
        XCTAssertNotEqual(opaqueClip.url, clip.url)
        XCTAssertEqual(store.settings, settings)
        XCTAssertEqual(store.library.map(\\.id), library)
        XCTAssertEqual(try Data(contentsOf: opaqueClip.url), original)
        XCTAssertEqual(try Data(contentsOf: opaque), original)
        XCTAssertEqual(try Data(contentsOf: mp4), original)
'''

def main():
    edits = {}
    def replace(relative, before, after):
        path = ROOT / relative
        text = edits.get(path, path.read_text())
        if after in text:
            return
        if text.count(before) != 1:
            raise RuntimeError(f'Unexpected source in {relative}; refusing an ambiguous patch.')
        edits[path] = text.replace(before, after, 1)
    policy = ROOT / 'App/VideoFileImportPolicy.swift'
    existing = policy.read_text()
    assert 'static let allowedContentTypes: [UTType] = [.item]' in existing
    if 'static func stagingFilename' in existing and existing != POLICY:
        raise RuntimeError('Existing container normalization differs; refusing to overwrite it.')
    edits[policy] = POLICY
    replace('App/AppStore.swift',
            'let result = folder.appendingPathComponent(source.lastPathComponent)',
            'let result = folder.appendingPathComponent(try VideoFileImportPolicy.stagingFilename(for: readable, originalName: source.lastPathComponent))')
    # A made-up importedAs identifier has no declared type hierarchy. Use the
    # system's actual dynamic-UTI factory to model a generic provider file.
    replace('Tests/LumaLiftTests.swift',
            'let generic = UTType(importedAs: "com.billy.lucid.tests.provider-data", conformingTo: .data)',
            'let generic = UTType(filenameExtension: "lucid-provider-opaque-fixture", conformingTo: .data)!\n        XCTAssertTrue(generic.conforms(to: .data))')
    replace('Tests/LumaLiftTests.swift',
            '        XCTAssertEqual(try Data(contentsOf: mp4), original)\n    }\n',
            '        XCTAssertEqual(try Data(contentsOf: mp4), original)\n' + EXTRA_MP4 + '    }\n')
    for path, text in edits.items():
        path.write_text(text)
    print('Preserved all import assertions; added private MOV/MP4 container hints and a genuine dynamic-UTI fixture.')
    # Start the same simulator the native builder selects while models and
    # binaries are prepared. The builder still waits for a full successful boot.
    if sys.platform == 'darwin':
        data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json'],text=True))
        candidates=[]
        for runtime, devices in data['devices'].items():
            version=re.search(r'iOS-(\d+)(?:-(\d+))?',runtime)
            if version and int(version[1])>=26:
                for device in devices:
                    if device.get('isAvailable') and device['name'].startswith('iPhone'):
                        candidates.append(((int(version[1]),int(version[2] or 0),'Pro' in device['name'],device['name']),device))
        if candidates:
            device=max(candidates,key=lambda pair:pair[0])[1]
            if device['state']!='Booted':
                subprocess.run(['xcrun','simctl','boot',device['udid']],check=True)

if __name__ == '__main__':
    main()
