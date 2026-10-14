import Foundation
import CryptoKit
import Darwin

struct GGUFInfo: Equatable, Sendable {
    let name: String
    let architecture: String
    let bytes: Int64
    var dimensions: [String: UInt64] = [:]
}

/// Bounded I/O only: no full-file Data, no per-chunk autoreleased NSData, and
/// no tensor materialization just to install or inspect a model.
enum GGUFInspector {
    static let supported: Set<String> = ["llama","qwen2","qwen3","qwen3moe","qwen35","qwen35moe","gemma","gemma2","gemma3","gemma4","lfm2","lfm2moe","phi2","phi3","gpt2","gptoss","deepseek2","smollm3","granite","minicpm","mistral3"]
    static let hashBufferBytes = 512 * 1024
    static func inspect(_ url: URL) throws -> GGUFInfo {
        let r = try Reader(url)
        guard try r.take(4) == Data([0x47,0x47,0x55,0x46]) else { throw RiftFailure("Choose a GGUF chat model, not a ZIP, adapter, or SafeTensors file.") }
        let version: UInt32 = try r.number()
        guard version == 2 || version == 3 else { throw RiftFailure("This GGUF version is not supported.") }
        let tensors: UInt64 = try r.number(), metadata: UInt64 = try r.number()
        guard tensors > 0, tensors <= 200_000, metadata > 0, metadata <= 20_000 else { throw RiftFailure("The GGUF header is invalid.") }
        var architecture = "", name = url.deletingPathExtension().lastPathComponent, hasTemplate = false
        var dimensions: [String:UInt64] = [:]
        let suffixes = ["block_count", "attention.head_count_kv", "attention.head_count", "attention.key_length", "attention.value_length", "embedding_length", "full_attention_interval"]
        for _ in 0..<metadata {
            try Task.checkCancellation()
            guard r.offset < 128 * 1024 * 1024 else { throw RiftFailure("This model's metadata is too large to import safely.") }
            let key = try r.string(limit: 8192), type: UInt32 = try r.number()
            if type == 8 && ["general.architecture", "general.name", "tokenizer.chat_template"].contains(key) {
                let text = try r.string(limit: 2 * 1024 * 1024)
                if key == "general.architecture" { architecture = text }
                if key == "general.name" { name = String(text.prefix(120)) }
                if key == "tokenizer.chat_template" { hasTemplate = !text.isEmpty }
            } else if key == "split.count" {
                guard try r.integer(type: type) <= 1 else { throw RiftFailure("Import a single-file GGUF. Split models are not supported.") }
            } else if [0,1,2,3,4,5,10,11].contains(type), let suffix = suffixes.first(where: { key.hasSuffix("." + $0) }) {
                dimensions[suffix] = try r.integer(type: type)
            } else { try r.skip(type: type) }
        }
        guard supported.contains(architecture) else { throw RiftFailure("The \(architecture.isEmpty ? "unknown" : architecture) architecture is not supported by this Rift build. Vision projectors are not chat models.") }
        guard hasTemplate else { throw RiftFailure("This GGUF has no chat template. Import an instruction/chat version with tokenizer.chat_template metadata.") }
        guard r.size > r.offset + 64 else { throw RiftFailure("This GGUF is incomplete.") }
        return .init(name: name, architecture: architecture, bytes: Int64(r.size), dimensions: dimensions)
    }
    static func hash(_ url: URL, progress: (@Sendable (Double) -> Void)? = nil) throws -> String {
        let fd = url.withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY) }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw POSIXError(.EIO) }
        let size = max(Int64(1), Int64(info.st_size))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: hashBufferBytes, alignment: 64)
        defer { buffer.deallocate() }
        var hasher = SHA256(), processed: Int64 = 0
        var lastUpdate = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, buffer, hashBufferBytes)
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            processed += Int64(count)
            // A UI notification at most five times a second, never per disk chunk.
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastUpdate >= 0.2 { progress?(min(1, Double(processed) / Double(size))); lastUpdate = now }
        }
        guard processed == info.st_size else { throw RiftFailure("The model changed while it was being verified. Nothing was installed.") }
        progress?(1)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private final class Reader {
        let fd: Int32
        let size: UInt64
        var offset: UInt64 = 0
        private var window = [UInt8](repeating: 0, count: 64 * 1024)
        private var windowStart: UInt64 = 0
        private var windowCount = 0
        init(_ url: URL) throws {
            let descriptor = url.withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY) }
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_size >= 24, info.st_size <= 40 * 1024 * 1024 * 1024 else {
                Darwin.close(descriptor); throw RiftFailure("This file is empty, incomplete, or too large for Rift.")
            }
            fd = descriptor; size = UInt64(info.st_size)
        }
        deinit { Darwin.close(fd) }
        private func refill() throws {
            if offset >= windowStart && offset < windowStart + UInt64(windowCount) { return }
            let wanted = Int(min(UInt64(window.count), size - offset))
            var count: Int
            repeat {
                count = window.withUnsafeMutableBytes { Darwin.pread(fd, $0.baseAddress!, wanted, off_t(offset)) }
            } while count < 0 && errno == EINTR
            guard count > 0 else { throw RiftFailure("The GGUF is truncated or cannot be read.") }
            windowStart = offset; windowCount = count
        }
        func take(_ count: Int) throws -> Data {
            guard count >= 0, UInt64(count) <= size - offset, count <= 4 * 1024 * 1024 else { throw RiftFailure("The GGUF contains an invalid length.") }
            var result = Data(count: count)
            try result.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
                var written = 0
                while written < count {
                    try refill()
                    let start = Int(offset - windowStart), amount = min(count - written, windowCount - start)
                    window.withUnsafeBytes { source in
                        target.baseAddress!.advanced(by: written).copyMemory(from: source.baseAddress!.advanced(by: start), byteCount: amount)
                    }
                    offset += UInt64(amount); written += amount
                }
            }
            return result
        }
        func number<T: FixedWidthInteger>() throws -> T {
            guard UInt64(MemoryLayout<T>.size) <= size - offset else { throw RiftFailure("The GGUF is truncated.") }
            var value: T = 0
            for index in 0..<MemoryLayout<T>.size {
                try refill()
                value |= T(truncatingIfNeeded: window[Int(offset - windowStart)]) << (index * 8)
                offset += 1
            }
            return value
        }
        func string(limit: Int) throws -> String {
            let n: UInt64 = try number()
            guard n <= UInt64(limit) else { throw RiftFailure("A GGUF string exceeds the import limit.") }
            guard let s = String(data: try take(Int(n)), encoding: .utf8) else { throw RiftFailure("This GGUF has invalid UTF-8 metadata.") }
            return s
        }
        func seek(_ count: UInt64) throws {
            guard count <= size - offset else { throw RiftFailure("The GGUF is truncated.") }
            offset += count
        }
        func integer(type: UInt32) throws -> UInt64 {
            switch type {
            case 0,1,7: let n:UInt8 = try number(); return UInt64(n)
            case 2,3: let n:UInt16 = try number(); return UInt64(n)
            case 4,5: let n:UInt32 = try number(); return UInt64(n)
            case 10,11: return try number()
            default: throw RiftFailure("Invalid GGUF integer field.")
            }
        }
        func skip(type: UInt32) throws {
            let lengths: [UInt32:UInt64] = [0:1,1:1,7:1,2:2,3:2,4:4,5:4,6:4,10:8,11:8,12:8]
            if let length = lengths[type] { try seek(length); return }
            if type == 8 {
                let n:UInt64 = try number()
                guard n <= 4 * 1024 * 1024 else { throw RiftFailure("A GGUF string is too large.") }
                try seek(n); return
            }
            if type == 9 {
                let element:UInt32 = try number(), count:UInt64 = try number()
                guard count <= 2_000_000, element != 9 else { throw RiftFailure("Unsupported GGUF metadata array.") }
                if let stride = lengths[element] { try seek(stride * count); return }
                guard element == 8 else { throw RiftFailure("Unknown GGUF array type.") }
                for index in 0..<count {
                    if index % 4096 == 0 { try Task.checkCancellation() }
                    try skip(type: element)
                }
                return
            }
            throw RiftFailure("This GGUF has an unknown metadata type.")
        }
    }
}
