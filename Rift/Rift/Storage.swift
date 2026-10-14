import Foundation

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
