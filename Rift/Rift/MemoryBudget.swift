import Foundation

struct InferencePlan: Equatable, Sendable {
    let context: Int
    let required: UInt64
    let reduced: Bool
}
struct MemoryBudget {
    static let headroom: UInt64 = 160 * 1_048_576
    /// Estimate working allocations using model metadata, not a fixed multi-GB
    /// marketing tier. It is advisory: the OS allowance is checked again at load.
    static func required(bytes: Int64, context: Int, workingGB: Double? = nil, architecture: String = "", dimensions: [String:UInt64] = [:]) -> UInt64 {
        func value(_ key: String, fallback: Int, max bound: Int = 65536) -> Int {
            guard let raw = dimensions[key], raw > 0, raw <= UInt64(bound) else { return fallback }
            return Int(raw)
        }
        let recurrent = ["qwen35", "qwen35moe", "lfm2", "lfm2moe"].contains(architecture)
        var layers = value("block_count", fallback: recurrent ? 32 : 40, max: 256)
        if recurrent { layers = max(1, layers / value("full_attention_interval", fallback: 4, max: 32)) }
        let heads = value("attention.head_count_kv", fallback: 8, max: 256)
        let key = value("attention.key_length", fallback: recurrent ? 256 : 128, max: 2048)
        let val = value("attention.value_length", fallback: key, max: 2048)
        let kv = UInt64(max(512, min(8192, context))) * UInt64(layers * heads * (key + val) * 2)
        let workspace: UInt64 = (recurrent ? 288 : 224) * 1_048_576
        let weights = UInt64(max(0, bytes))
        return weights + workspace + kv
    }
    static func fits(required: UInt64, available: UInt64) -> Bool {
        available > headroom && required <= available - headroom
    }
    static func plan(bytes: Int64, requested: Int, available: UInt64, architecture: String, dimensions: [String:UInt64] = [:]) -> InferencePlan? {
        let start = max(512, min(8192, requested))
        let options = [start] + [4096, 2048, 1024, 512].filter { $0 < start }
        for context in options {
            let need = required(bytes: bytes, context: context, architecture: architecture, dimensions: dimensions)
            if fits(required: need, available: available) { return .init(context: context, required: need, reduced: context < requested) }
        }
        return nil
    }
    static func label(_ bytes: UInt64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }
    static func blockedMessage(bytes: Int64, available: UInt64, architecture: String, dimensions: [String:UInt64]) -> String {
        let need = required(bytes: bytes, context: 512, architecture: architecture, dimensions: dimensions) + headroom
        return "This model needs about \(label(need)); this installation currently reports \(label(available)) available to the app. Rift tried its shorter context settings. A signed increased-memory-limit entitlement may help; inside LiveContainer the host controls that allowance. The phone's total RAM is not the app's memory limit."
    }
}
