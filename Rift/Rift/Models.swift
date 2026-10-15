import Foundation
import Darwin

struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let family: String
    let variant: String
    let badge: String
    let detail: String
    let repo: String
    let revision: String
    let filename: String
    let bytes: Int64
    let sha256: String
    let architecture: String
    let minimumRAM: Int
    let workingGB: Double
    let rank: Int
    let license: String
    let licenseText: String
    let uncensored: Bool
    var group: String? = nil
    var experimental: Bool? = nil
    var libraryGroup: String { group ?? (family == "Liquid" ? "Heretic" : family) }
    var downloadURL: URL { URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")! }
    var sourceURL: URL { URL(string: "https://huggingface.co/\(repo)/tree/\(revision)")! }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
struct InstalledModel: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var filename: String
    var bytes: Int64
    var sha256: String
    var architecture: String
    var catalogID: String?
    var importedAt: Date
    var isCustom: Bool { catalogID == nil }
}
struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var role: String
    var content: String
    var modelName: String?
    var interrupted = false
    var failureDescription: String? = nil
    var attachments: [ChatAttachment]? = nil
    var isFailedReply: Bool { failureDescription != nil || (interrupted && (content.hasPrefix("No reply was generated.") || content == "Reply stopped.")) }
    var canSendToModel: Bool { !content.isEmpty && !isFailedReply }
}
struct Conversation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = "New chat"
    var messages: [ChatMessage] = []
    var updatedAt = Date()
    var transcript: String { messages.map { "\($0.role == "user" ? "You" : "Rift")\n\($0.content)" }.joined(separator: "\n\n") }
}
struct DeviceProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let ram: Int
    static let profiles: [DeviceProfile] = [
        .init(id:"14",name:"iPhone 14 / 14 Plus",ram:6), .init(id:"14pro",name:"iPhone 14 Pro / Pro Max",ram:6),
        .init(id:"15",name:"iPhone 15 / 15 Plus",ram:6), .init(id:"15pro",name:"iPhone 15 Pro / Pro Max",ram:8),
        .init(id:"16",name:"iPhone 16 / 16 Plus / 16e",ram:8), .init(id:"16pro",name:"iPhone 16 Pro / Pro Max",ram:8),
        .init(id:"17",name:"iPhone 17 / 17e",ram:8), .init(id:"17pro",name:"iPhone 17 Pro / Pro Max",ram:12),
        .init(id:"air",name:"iPhone Air",ram:12), .init(id:"18pro",name:"iPhone 18 Pro",ram:12),
        .init(id:"18promax",name:"iPhone 18 Pro Max",ram:12)
    ]
    static func profileID(machine: String) -> String? {
        let map: [String:String] = ["iPhone14,7":"14","iPhone14,8":"14","iPhone15,2":"14pro","iPhone15,3":"14pro","iPhone15,4":"15","iPhone15,5":"15","iPhone16,1":"15pro","iPhone16,2":"15pro","iPhone17,3":"16","iPhone17,4":"16","iPhone17,5":"16","iPhone17,1":"16pro","iPhone17,2":"16pro","iPhone18,1":"17pro","iPhone18,2":"17pro","iPhone18,3":"17","iPhone18,4":"air","iPhone18,5":"17","iPhone19,2":"18pro","iPhone19,3":"18promax","iPhone19,7":"18promax"]
        return map[machine]
    }
    static var machine: String {
        if let value = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return value }
        var system = utsname(); uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString:$0) } }
    }
    static var current: DeviceProfile {
        let identifier = machine
        let measured = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let match = profiles.first { $0.id == profileID(machine: identifier) }
        #if targetEnvironment(simulator)
        return match ?? profiles[7]
        #else
        return .init(id: match?.id ?? "current", name: match?.name ?? "This iPhone (\(identifier))", ram: measured)
        #endif
    }
    func models(from all: [CatalogModel]) -> [CatalogModel] {
        let eligible = all.filter { $0.uncensored && $0.minimumRAM <= ram }
        return ["Heretic", "Qwen", "Gemma"].flatMap { group in
            eligible.filter { $0.libraryGroup == group }.sorted { $0.rank > $1.rank }
        }
    }
    static func featured(_ models: [CatalogModel]) -> [CatalogModel] {
        let normal=models.filter { $0.experimental != true }.sorted { $0.rank > $1.rank }
        let large=models.filter { $0.experimental == true }.sorted { $0.bytes < $1.bytes }
        if let preview=large.first { return Array(normal.prefix(1)) + [preview] }
        return Array(normal.prefix(2))
    }
}
struct ReplyParts: Equatable {
    let thought: String
    let answer: String
    static func parse(_ raw: String) -> ReplyParts {
        if let start = raw.range(of:"<think>") {
            let rest = String(raw[start.upperBound...])
            if let end = rest.range(of:"</think>") {
                return .init(thought:String(rest[..<end.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines), answer:String(rest[end.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines))
            }
            return .init(thought:rest,answer:"")
        }
        return .init(thought:"",answer:raw)
    }
}
struct RiftFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
