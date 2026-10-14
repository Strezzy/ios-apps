import Foundation
import CryptoKit

struct GGUFInfo: Equatable, Sendable { let name: String; let architecture: String; let bytes: Int64 }
enum GGUFInspector {
    static let supported: Set<String> = ["llama","qwen2","qwen3","qwen3moe","qwen35","qwen35moe","gemma","gemma2","gemma3","gemma4","lfm2","lfm2moe","phi2","phi3","gpt2","gptoss","deepseek2","smollm3","granite","minicpm","mistral3"]
    static func inspect(_ url: URL) throws -> GGUFInfo {
        let r = try Reader(url)
        guard try r.take(4) == Data([0x47,0x47,0x55,0x46]) else { throw RiftFailure("Choose a GGUF language model, not a ZIP, adapter, or SafeTensors file.") }
        let version: UInt32 = try r.number()
        guard version == 2 || version == 3 else { throw RiftFailure("This GGUF version is not supported.") }
        let tensors: UInt64 = try r.number(), metadata: UInt64 = try r.number()
        guard tensors > 0, tensors <= 200_000, metadata > 0, metadata <= 20_000 else { throw RiftFailure("The GGUF header is invalid.") }
        var architecture = "", name = url.deletingPathExtension().lastPathComponent, hasTemplate = false
        for _ in 0..<metadata {
            try Task.checkCancellation()
            guard r.offset < 128*1024*1024 else { throw RiftFailure("This model's metadata is too large to import safely.") }
            let key = try r.string(limit:8192), type: UInt32 = try r.number()
            if type == 8 && ["general.architecture","general.name","tokenizer.chat_template"].contains(key) {
                let text = try r.string(limit:2*1024*1024)
                if key == "general.architecture" { architecture = text }
                if key == "general.name" { name = String(text.prefix(120)) }
                if key == "tokenizer.chat_template" { hasTemplate = !text.isEmpty }
            } else if key == "split.count" {
                let count = try r.integer(type:type)
                guard count <= 1 else { throw RiftFailure("Split GGUF models are not supported yet. Import a single-file quantization.") }
            } else { try r.skip(type:type) }
        }
        guard supported.contains(architecture) else { throw RiftFailure("The \(architecture.isEmpty ? "unknown" : architecture) architecture is not supported by this Rift build. Vision projectors and embedding-only models cannot be used for chat.") }
        guard hasTemplate else { throw RiftFailure("This GGUF has no chat template. Import an instruction/chat version with a tokenizer.chat_template field.") }
        guard r.size > r.offset+64 else { throw RiftFailure("This GGUF is incomplete.") }
        return .init(name:name,architecture:architecture,bytes:Int64(r.size))
    }
    static func hash(_ url: URL, progress: (@Sendable (Double) -> Void)? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        let size = (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 1
        var hasher = SHA256(), read = 0
        while let data = try handle.read(upToCount:1_048_576), !data.isEmpty {
            try Task.checkCancellation(); hasher.update(data:data); read += data.count
            if read % (32*1_048_576) < 1_048_576 { progress?(Double(read)/Double(max(1,size))) }
        }
        return hasher.finalize().map { String(format:"%02x",$0) }.joined()
    }
    private final class Reader {
        let handle: FileHandle
        let size: UInt64
        var offset: UInt64 = 0
        init(_ url: URL) throws {
            handle = try FileHandle(forReadingFrom:url)
            size = try handle.seekToEnd(); try handle.seek(toOffset:0)
            guard size >= 24, size <= 40*1024*1024*1024 else { throw RiftFailure("This file is empty, incomplete, or too large for Rift.") }
        }
        deinit { try? handle.close() }
        func take(_ count: Int) throws -> Data {
            guard count >= 0, UInt64(count) <= size-offset, count <= 4*1024*1024 else { throw RiftFailure("The GGUF contains an invalid length.") }
            guard let d = try handle.read(upToCount:count), d.count == count else { throw RiftFailure("The GGUF is truncated.") }
            offset += UInt64(count); return d
        }
        func number<T: FixedWidthInteger>() throws -> T {
            let d = try take(MemoryLayout<T>.size)
            return d.withUnsafeBytes { T(littleEndian:$0.loadUnaligned(as:T.self)) }
        }
        func string(limit: Int) throws -> String {
            let n: UInt64 = try number()
            guard n <= UInt64(limit) else { throw RiftFailure("A GGUF string exceeds the import limit.") }
            let d = try take(Int(n))
            guard let s = String(data:d,encoding:.utf8) else { throw RiftFailure("This GGUF has invalid UTF-8 metadata.") }
            return s
        }
        func seek(_ count: UInt64) throws {
            guard count <= size-offset else { throw RiftFailure("The GGUF is truncated.") }
            offset += count; try handle.seek(toOffset:offset)
        }
        func integer(type: UInt32) throws -> UInt64 {
            switch type { case 0,1,7: let n:UInt8=try number(); return UInt64(n)
            case 2,3: let n:UInt16=try number(); return UInt64(n)
            case 4,5: let n:UInt32=try number(); return UInt64(n)
            case 10,11: return try number()
            default: throw RiftFailure("Invalid GGUF integer field.") }
        }
        func skip(type: UInt32) throws {
            switch type {
            case 0,1,7: try seek(1)
            case 2,3: try seek(2)
            case 4,5,6: try seek(4)
            case 10,11,12: try seek(8)
            case 8: let n:UInt64=try number(); guard n <= 4*1024*1024 else { throw RiftFailure("A GGUF string is too large.") }; try seek(n)
            case 9:
                let element: UInt32=try number(), count:UInt64=try number()
                guard element != 9, count <= 2_000_000 else { throw RiftFailure("The GGUF has an unsupported metadata array.") }
                for index in 0..<count { if index % 4096 == 0 { try Task.checkCancellation() }; try skip(type:element) }
            default: throw RiftFailure("This GGUF has an unknown metadata type.")
            }
        }
    }
}
