import Foundation
import CryptoKit

struct LocalStorage: Sendable {
    let root: URL
    let models: URL
    let transfers: URL
    init(root: URL? = nil) throws {
        let base = try root ?? FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("Rift",isDirectory:true)
        self.root=base; models=base.appendingPathComponent("Models",isDirectory:true); transfers=base.appendingPathComponent("Transfers",isDirectory:true)
        for directory in [base,models,transfers] {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var value=directory; var resources=URLResourceValues(); resources.isExcludedFromBackup=true; try value.setResourceValues(resources)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:directory.path)
            #endif
        }
    }
    func url(for model: InstalledModel) -> URL { models.appendingPathComponent(model.filename) }
    func read<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let url=root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath:url.path) else { return fallback }
        return try JSONDecoder().decode(T.self,from:Data(contentsOf:url))
    }
    func write<T: Encodable>(_ value: T, name: String) throws {
        let data=try JSONEncoder().encode(value)
        try writeData(data, name: name)
    }
    func writeData(_ data: Data, name: String) throws {
        let url=root.appendingPathComponent(name)
        try data.write(to:url,options:.atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:url.path)
        #endif
    }
    func freeSpace() -> Int64 {
        let values=try? root.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

/// Confined to AppModel's serial persistence queue. Streaming checkpoints hold
/// only the active chat; chats.json remains the canonical, compatible full save.
final class ConversationPersistence: @unchecked Sendable {
    private struct Checkpoint: Codable {
        let baseDigest: String
        let conversation: Conversation
    }
    private static let checkpointName = "chat-checkpoint.json"
    private var baseDigest: String?
    private var savedModels: [InstalledModel]?

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func read(from storage: LocalStorage) throws -> [Conversation] {
        let url = storage.root.appendingPathComponent("chats.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        var chats = try JSONDecoder().decode([Conversation].self, from: data)
        // A stale or damaged checkpoint must never replace a newer full save.
        if let checkpointData = try? Data(contentsOf: storage.root.appendingPathComponent(checkpointName)),
           let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: checkpointData),
           checkpoint.baseDigest == digest(data),
           let index = chats.firstIndex(where: { $0.id == checkpoint.conversation.id }) {
            chats[index] = checkpoint.conversation
        }
        return chats
    }

    func save(chats: [Conversation], models: [InstalledModel], to storage: LocalStorage) throws {
        let data = try JSONEncoder().encode(chats)
        try storage.writeData(data, name: "chats.json")
        baseDigest = Self.digest(data)
        // The digest makes recovery safe even if checkpoint removal fails.
        try? FileManager.default.removeItem(at: storage.root.appendingPathComponent(Self.checkpointName))
        if savedModels != models {
            try storage.write(models, name: "models.json")
            savedModels = models
        }
    }

    func checkpoint(_ chat: Conversation, to storage: LocalStorage) throws {
        // Only checkpoint after a successful full save on this same queue.
        guard let baseDigest else { return }
        try storage.write(Checkpoint(baseDigest: baseDigest, conversation: chat), name: Self.checkpointName)
    }
}
