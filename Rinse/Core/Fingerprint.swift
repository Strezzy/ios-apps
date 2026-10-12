import Foundation
import CryptoKit

/// A byte hash is not a visual fingerprint. Padding contains random bytes only.
enum Fingerprint {
    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func be32(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb8_8320 : 0) }
        }
        return crc ^ 0xffff_ffff
    }
    static func randomize(_ url: URL) throws {
        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0..<24).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        switch url.pathExtension.lowercased() {
        case "png":
            let file = try FileHandle(forUpdating: url)
            defer { try? file.close() }
            let end = try file.seekToEnd()
            guard end >= 12 else { throw RinseError.message("Invalid PNG output.") }
            try file.seek(toOffset: end - 12)
            let tail = try file.read(upToCount: 12) ?? Data()
            guard tail.count == 12, tail.subdata(in: 4..<8) == Data("IEND".utf8) else {
                throw RinseError.message("PNG terminator could not be verified.")
            }
            // An ancillary, private, safe-to-copy PNG chunk, inserted before IEND.
            let payload = Data("riNs".utf8) + nonce
            try file.seek(toOffset: end - 12)
            try file.write(contentsOf: be32(UInt32(nonce.count)) + payload + be32(crc32(payload)) + tail)
        case "jpg", "jpeg":
            let temporary = url.appendingPathExtension("padding")
            defer { try? FileManager.default.removeItem(at: temporary) }
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let input = try FileHandle(forReadingFrom: url)
            let output = try FileHandle(forWritingTo: temporary)
            do {
                guard try input.read(upToCount: 2) == Data([0xff, 0xd8]) else {
                    throw RinseError.message("Invalid JPEG output.")
                }
                // APP15 has no EXIF/XMP payload, identity, timestamp or device identifier.
                let count = nonce.count + 2
                try output.write(contentsOf: Data([0xff, 0xd8, 0xff, 0xef, UInt8(count >> 8), UInt8(count & 255)]) + nonce)
                while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                    try Task.checkCancellation(); try output.write(contentsOf: data)
                }
                try input.close(); try output.close()
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } catch {
                try? input.close(); try? output.close(); throw error
            }
        case "heic", "heif", "mp4", "mov", "m4v":
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            _ = try file.seekToEnd()
            // ISO BMFF 'free' space has no media meaning and preserves sample offsets.
            try file.write(contentsOf: be32(UInt32(nonce.count + 8)) + Data("free".utf8) + nonce)
        default: throw RinseError.message("Fresh fingerprints are not supported for this format.")
        }
    }
}
