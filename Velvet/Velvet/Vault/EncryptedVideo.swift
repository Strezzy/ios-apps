import CryptoKit
import Foundation

struct VaultFinishedVideo {
    let manifest: VaultBlobReference
    let byteCount: Int64
    let contentHash: String
}

final class VaultVideoWriter: VaultRevocable, @unchecked Sendable {
    static let maximumSegmentBytes = 32 * 1_024 * 1_024
    let id: UUID
    let width: Int?
    let height: Int?
    let fileExtension: String
    let directory: URL
    let wrappedKey: Data
    let session: VaultSession
    private let mutex = NSLock()
    private var itemKey: SymmetricKey?
    private var segments: [VaultVideoSegment] = []
    private var totalBytes: Int64 = 0
    private var hasher = SHA256()
    private enum State { case recording, prepared, committed, cancelled }
    private var state = State.recording

    init(id: UUID, key: SymmetricKey, wrappedKey: Data, directory: URL, session: VaultSession,
         fileExtension: String, width: Int?, height: Int?) {
        self.id = id
        self.itemKey = key
        self.wrappedKey = wrappedKey
        self.directory = directory
        self.session = session
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        session.register(self, itemID: id)
    }

    func append(_ data: Data, isInitialization: Bool) throws {
        mutex.lock()
        defer { mutex.unlock() }
        try session.requireActive()
        guard state == .recording, let key = itemKey,
              !data.isEmpty, data.count <= Self.maximumSegmentBytes,
              segments.count < 1_000_000,
              isInitialization == segments.isEmpty else { throw VaultError.invalidVideo }
        let sequence = segments.count
        let encrypted = try VaultCrypto.seal(data, key: key, domain: "video.segment", assetID: id, sequence: UInt64(sequence))
        try ProtectedFiles.write(encrypted, to: Self.segmentURL(directory: directory, index: sequence))
        try session.requireActive()
        segments.append(VaultVideoSegment(sequence: sequence, byteCount: data.count,
            isInitialization: isInitialization, ciphertextHash: VaultCrypto.digest(encrypted)))
        totalBytes += Int64(data.count)
        hasher.update(data: data)
    }

    func prepareToCommit() throws -> VaultFinishedVideo {
        mutex.lock()
        defer { mutex.unlock() }
        try session.requireActive()
        guard state == .recording, let key = itemKey else { throw VaultError.invalidVideo }
        let manifest = VaultVideoManifest(format: 1, assetID: id, segments: segments, totalByteCount: totalBytes)
        try manifest.validate(expectedID: id)
        let ciphertext = try VaultCrypto.seal(JSONEncoder().encode(manifest), key: key, domain: "video.manifest", assetID: id)
        try ProtectedFiles.write(ciphertext, to: directory.appendingPathComponent("manifest.vlt"))
        try session.requireActive()
        state = .prepared
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return VaultFinishedVideo(manifest: VaultBlobReference(filename: "manifest.vlt", ciphertextHash: VaultCrypto.digest(ciphertext)),
            byteCount: totalBytes, contentHash: digest)
    }

    func encryptThumbnail(_ thumbnail: Data) throws -> VaultBlobReference {
        mutex.lock()
        defer { mutex.unlock() }
        try session.requireActive()
        guard state == .prepared, let key = itemKey,
              thumbnail.count <= 8 * 1_024 * 1_024 else { throw VaultError.invalidVideo }
        let ciphertext = try VaultCrypto.seal(thumbnail, key: key, domain: "thumbnail", assetID: id)
        let reference = VaultBlobReference(filename: "thumbnail.vlt", ciphertextHash: VaultCrypto.digest(ciphertext))
        try ProtectedFiles.write(ciphertext, to: directory.appendingPathComponent(reference.filename))
        return reference
    }

    func markCommitted() {
        mutex.lock()
        defer { mutex.unlock() }
        state = .committed
        itemKey = nil
        segments.removeAll()
    }

    func cancel() { revoke() }

    func revoke() {
        mutex.lock()
        defer { mutex.unlock() }
        itemKey = nil
        segments.removeAll()
        // A committed record owns this directory. Only the catalogue may delete it.
        if state == .recording || state == .cancelled {
            state = .cancelled
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func segmentURL(directory: URL, index: Int) -> URL {
        directory.appendingPathComponent(String(format: "segment-%08d.vlt", index))
    }
}

final class VaultVideoReader: VaultRevocable, @unchecked Sendable {
    static let maximumReadBytes = 32 * 1_024 * 1_024
    let totalLength: Int64
    let contentType = "video/mp4"
    let assetID: UUID
    private let directory: URL
    private let manifest: VaultVideoManifest
    private let offsets: [Int64]
    private let session: VaultSession
    private let mutex = NSLock()
    private var itemKey: SymmetricKey?
    private var cachedIndex: Int?
    private var cachedPlaintext: Data?

    init(manifest: VaultVideoManifest, directory: URL, key: SymmetricKey, session: VaultSession) throws {
        try manifest.validate(expectedID: manifest.assetID)
        self.manifest = manifest
        self.totalLength = manifest.totalByteCount
        self.assetID = manifest.assetID
        self.directory = directory
        self.itemKey = key
        self.session = session
        var positions: [Int64] = []
        var current: Int64 = 0
        for segment in manifest.segments {
            positions.append(current)
            current += Int64(segment.byteCount)
        }
        self.offsets = positions
        session.register(self, itemID: assetID)
    }

    func read(offset: Int64, length: Int) throws -> Data {
        mutex.lock()
        defer { mutex.unlock() }
        try session.requireActive()
        guard let key = itemKey else { throw VaultError.locked }
        guard offset >= 0, length >= 0, length <= Self.maximumReadBytes,
              offset <= totalLength, Int64(length) <= totalLength - offset else { throw VaultError.invalidRange }
        if length == 0 { return Data() }
        var output = Data()
        output.reserveCapacity(length)
        let end = offset + Int64(length)
        // Binary search for the segment containing the first requested byte.
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if offsets[middle] <= offset { lower = middle + 1 } else { upper = middle }
        }
        var index = max(0, lower - 1)
        var position = offset
        while position < end {
            try session.requireActive()
            guard index < manifest.segments.count else { throw VaultError.invalidVideo }
            let descriptor = manifest.segments[index]
            let plaintext: Data
            if cachedIndex == index, let cachedPlaintext {
                plaintext = cachedPlaintext
            } else {
                let ciphertext = try ProtectedFiles.read(VaultVideoWriter.segmentURL(directory: directory, index: index),
                    maximumBytes: VaultVideoWriter.maximumSegmentBytes + 64)
                guard VaultCrypto.digest(ciphertext) == descriptor.ciphertextHash else { throw VaultError.integrityFailure }
                plaintext = try VaultCrypto.open(ciphertext, key: key, domain: "video.segment", assetID: assetID, sequence: UInt64(index))
                guard plaintext.count == descriptor.byteCount else { throw VaultError.integrityFailure }
                cachedIndex = index
                cachedPlaintext = plaintext
            }
            let within = Int(position - offsets[index])
            let count = min(descriptor.byteCount - within, Int(end - position))
            guard count > 0 else { throw VaultError.invalidVideo }
            output.append(plaintext.subdata(in: within..<(within + count)))
            position += Int64(count)
            index += 1
        }
        try session.requireActive()
        return output
    }

    func revoke() {
        mutex.lock()
        defer { mutex.unlock() }
        itemKey = nil
        cachedIndex = nil
        cachedPlaintext = nil
    }

    func invalidate() { revoke() }
}
