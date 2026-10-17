import Foundation
import SwiftUI
import UIKit

final class InferenceService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.billy.rift.inference", qos: .userInitiated)
    // This object is cheap; the backend itself is initialized only on this queue.
    private let engine = RiftEngine()
    private var loadedID: String?
    private var loadedContext = 0
    func prepare() { engine.resetCancellation() }
    func stop() { engine.cancel() }
    func unload() {
        engine.cancel()
        queue.async { self.engine.unload(); self.loadedID = nil; self.loadedContext = 0 }
    }
    func release() async {
        engine.cancel()
        await withCheckedContinuation { continuation in
            queue.async { self.engine.unload(); self.loadedID = nil; self.loadedContext = 0; continuation.resume() }
        }
    }
    func run(model: InstalledModel, url: URL, messages: [[String:String]], projector: URL? = nil, context: Int, maxTokens: Int, temperature: Float, thinking: Bool, workingGB: Double?, text: @escaping @Sendable (String)->Void, status: @escaping @Sendable (String)->Void) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.engine.cancelled { throw RiftFailure("Stopped.") }
                    guard FileManager.default.fileExists(atPath: url.path) else { throw RiftFailure("This model could not load because its file is missing. Download or import it again.") }
                    var chosenContext = self.loadedContext
                    if projector != nil || self.loadedID != model.id || self.loadedContext > context || RiftAvailableMemory() < MemoryBudget.headroom {
                        self.engine.unload(); self.loadedID = nil; self.loadedContext = 0
                        let info = try GGUFInspector.inspect(url)
                        let physicalAvailable = RiftAvailableMemory()
                        let visionReserve: UInt64 = projector == nil ? 0 : 1_100 * 1_048_576
                        guard projector == nil || physicalAvailable > visionReserve else { throw RiftFailure("This installation does not have enough available memory for image understanding.") }
                        let available = physicalAvailable - visionReserve
                        guard let plan = MemoryBudget.plan(bytes: model.bytes, requested: context, available: available, architecture: info.architecture, dimensions: info.dimensions) else {
                            if projector != nil { throw RiftFailure("Qwen3.5 4B image understanding needs more working memory than this installation currently has available (\(MemoryBudget.label(physicalAvailable))). Free memory or use a text-only chat.") }
                            throw RiftFailure(MemoryBudget.blockedMessage(bytes: model.bytes, available: available, architecture: info.architecture, dimensions: info.dimensions))
                        }
                        chosenContext = plan.context
                    }
                    if self.engine.cancelled { throw RiftFailure("Stopped.") }
                    #if targetEnvironment(simulator)
                    let cpu = true
                    #else
                    let cpu = false
                    #endif
                    var finalText = ""
                    if projector != nil && chosenContext < 1024 { throw RiftFailure("Image understanding needs at least a 1K conversation window and more available memory. Use a shorter text-only chat or free memory first.") }
                    _ = try self.engine.generate(atPath: url.path, projector: projector?.path, messages: messages, context: Int32(chosenContext), maxTokens: Int32(min(maxTokens, max(128, chosenContext / 2))), temperature: temperature, thinking: thinking, cpu: cpu,
                        token: { value in finalText = value; text(value) }, status: status)
                    self.loadedID = model.id; self.loadedContext = chosenContext
                    if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.engine.cancelled {
                        throw RiftFailure("The model ended its reply without producing text. Retry the reply. Your message has been kept.")
                    }
                    if !self.engine.cancelled { status(chosenContext < context ? "On device · \(chosenContext)-token context" : "On device") }
                    continuation.resume(returning: finalText)
                } catch {
                    self.engine.unload(); self.loadedID = nil; self.loadedContext = 0
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var ready = false
    @Published var availableMemory: UInt64 = 0
    @Published var memorySnapshot = AppMemorySnapshot()
    private var started = false
    private var bootstrapRoot: URL?
    @Published var catalog: [CatalogModel] = []
    @Published var installed: [InstalledModel] = []
    @Published var conversations: [Conversation] = []
    @Published var activeChatID: UUID?
    @Published var selectedModelID: String?
    @Published var error: String?
    @Published var startupError: String?
    @Published var generating = false
    @Published var status = "On device"
    @Published var transferID: String?
    @Published var transferProgress: Double = 0
    @Published var transferStatus = ""
    @Published var pausedID: String?
    @Published var importing = false
    @Published private var pausing = false
    @AppStorage("rift.context") var context = 2048
    @AppStorage("rift.maxTokens") var maxTokens = 1024
    @AppStorage("rift.temperature") var temperature = 0.7
    @AppStorage("rift.thinking") var thinking = false
    @AppStorage("rift.cellular") var cellular = false
    @AppStorage("rift.systemPrompt") var systemPrompt = RiftPersonality.defaultPrompt
    private(set) var storage: LocalStorage?
    let device = DeviceProfile.current
    private let inference = InferenceService()
    private var downloader: DownloadJob?
    private var transferTask: Task<Void,Never>?
    private var importTask: Task<InstalledModel,Error>?
    private var saveTask: Task<Void,Never>?
    private var generationID: UUID?
    private var pauseOperation: UUID?
    private var stopping = false
    private let diskQueue = DispatchQueue(label: "com.billy.rift.persistence", qos: .utility)
    var selectedModel: InstalledModel? { installed.first { $0.id == selectedModelID } }
    var activeChat: Conversation? { conversations.first { $0.id == activeChatID } }
    var busy: Bool { transferID != nil || importing || pausing }

    init(storageOverride: URL? = nil) {
        bootstrapRoot = storageOverride
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--rift-ui-fixture") {
            bootstrapRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Rift-UI-" + UUID().uuidString)
        }
        #endif
    }
    /// Called after SwiftUI has presented the first frame. No Metal/model load here.
    func bootstrap() async {
        guard !started else { return }; started = true
        PrivacyPreferences.migrate()
        RiftPersonality.migrate()
        let root = bootstrapRoot
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) { () throws -> (LocalStorage, [CatalogModel], [InstalledModel], [Conversation]) in
                let store = try LocalStorage(root: root)
                guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else { throw RiftFailure("The model catalog is missing.") }
                let catalog = try JSONDecoder().decode([CatalogModel].self, from: Data(contentsOf: url))
                guard !catalog.isEmpty, catalog.allSatisfy({ $0.uncensored && $0.sha256.count == 64 && $0.revision.count == 40 && $0.bytes > 0 }) else { throw RiftFailure("The model catalog did not pass validation.") }
                let installed: [InstalledModel] = try store.read("models.json", fallback: [])
                let existing = installed.filter { FileManager.default.fileExists(atPath: store.url(for: $0).path) }
                let chats: [Conversation] = try store.read("chats.json", fallback: [])
                return (store, catalog, existing, chats)
            }.value
            storage = snapshot.0; catalog = snapshot.1; installed = snapshot.2; conversations = snapshot.3
            selectedModelID = UserDefaults.standard.string(forKey: "rift.selectedModel")
            if selectedModel == nil { selectedModelID = installed.first?.id }
            activeChatID = conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id
            pausedID = catalog.first { item in
                FileManager.default.fileExists(atPath: snapshot.0.transfers.appendingPathComponent(item.id + ".resume").path) ||
                FileManager.default.fileExists(atPath: snapshot.0.transfers.appendingPathComponent(item.id + ".partial").path)
            }?.id
            ready = true; refreshMemory()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--rift-ui-fixture") { DebugChatFixture.install(in: self) }
            #endif
        } catch {
            startupError = "Rift could not open its local data. Existing files have been left untouched. \(error.localizedDescription)"
        }
    }
    func refreshMemory() {
        let snapshot = AppMemorySnapshot(remaining: RiftAvailableMemory(), footprint: RiftMemoryFootprint())
        memorySnapshot = snapshot
        availableMemory = snapshot.remaining
    }
    func releaseModelMemory() async {
        guard !generating, !busy else { return }
        await inference.release()
        refreshMemory()
    }
    func dismissError() { error = nil }
    private func save() {
        guard let storage, startupError == nil else { return }
        let chats = conversations, models = installed
        diskQueue.async { [weak self] in
            do { try storage.write(chats, name: "chats.json"); try storage.write(models, name: "models.json") }
            catch { let message = error.localizedDescription; Task { @MainActor in self?.error = "Could not save local data: " + message } }
        }
    }
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { try? await Task.sleep(for: .seconds(1)); self.saveTask = nil; self.save() }
    }
    func newChat() { guard !generating else { return }; activeChatID = nil; status = "On device" }
    func select(_ model: InstalledModel) {
        guard !generating else { return }
        inference.unload(); selectedModelID = model.id
        UserDefaults.standard.set(model.id, forKey: "rift.selectedModel")
    }
    func deleteModel(_ model: InstalledModel) {
        guard !generating, let storage else { return }
        inference.unload()
        do {
            try FileManager.default.removeItem(at: storage.url(for: model))
            installed.removeAll { $0.id == model.id }
            if selectedModelID == model.id { selectedModelID = installed.first?.id; UserDefaults.standard.set(selectedModelID, forKey: "rift.selectedModel") }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func deleteChat(_ chat: Conversation) {
        if generating && activeChatID == chat.id { stop() }
        if let storage, let files = try? AttachmentStore(storage: storage) { chat.messages.flatMap { $0.attachments ?? [] }.forEach(files.remove) }
        conversations.removeAll { $0.id == chat.id }
        if activeChatID == chat.id { activeChatID = nil }
        save()
    }
    func clearChats() {
        stop()
        if let storage, let files = try? AttachmentStore(storage: storage) {
            conversations.flatMap { $0.messages }.flatMap { $0.attachments ?? [] }.forEach(files.remove)
        }
        conversations = []; activeChatID = nil; save()
    }
    func stop() { guard generating else { return }; stopping = true; inference.stop(); status = "Stopping" }
    func background() {
        if generating { stop() }
        if transferStatus == "Downloading" { pauseDownload() }
        inference.unload(); save(); UIApplication.shared.isIdleTimerDisabled = false
    }
    @discardableResult func send(_ draft: String, attachments: [ChatAttachment] = []) -> Bool {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard attachments.count <= 1 else { error = "Attach one image or file per message."; return false }
        if attachments.contains(where: { $0.isImage }) {
            guard VisionDownload.supports(selectedModel), let storage, VisionDownload.installedURL(storage: storage) != nil else {
                error = "Select Qwen3.5 4B and download its image support before sending an image."; return false
            }
        }
        if text.isEmpty && !attachments.isEmpty { text = attachments[0].isImage ? "Describe this image." : "Read this file and summarize it." }
        guard !text.isEmpty, !generating, !busy, ready, selectedModel != nil, startupError == nil else { return false }
        guard text.utf8.count <= 100_000 else { error = "This message is too long. Use a shorter message."; return false }
        if activeChatID == nil { let chat = Conversation(); conversations.append(chat); activeChatID = chat.id }
        guard let index = conversations.firstIndex(where: { $0.id == activeChatID }) else { return false }
        if conversations[index].messages.isEmpty { conversations[index].title = String(text.prefix(60)) }
        conversations[index].messages.append(.init(role: "user", content: text, attachments: attachments.isEmpty ? nil : attachments))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--rift-ui-controls") {
            DebugChatFixture.reply(in: self, index: index)
            return true
        }
        #endif
        beginReply(); return true
    }
    func regenerate() {
        guard !generating, !busy, let index = conversations.firstIndex(where: { $0.id == activeChatID }), let last = conversations[index].messages.last, last.role == "assistant" else { return }
        conversations[index].messages.removeLast(); beginReply()
    }
    private func beginReply() {
        guard let model = selectedModel, let storage, let index = conversations.firstIndex(where: { $0.id == activeChatID }) else { return }
        guard ProcessInfo.processInfo.thermalState != .critical && ProcessInfo.processInfo.thermalState != .serious else { error = "Your iPhone needs to cool down before generating another reply."; save(); return }
        error = nil
        let chatID = conversations[index].id, replyID = UUID(), operation = UUID()
        var messages = [[String:String]]()
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append(["role": "system", "content": String(systemPrompt.prefix(8000))]) }
        let turns = conversations[index].messages.filter { $0.canSendToModel }
        let hasImages = turns.contains { ($0.attachments ?? []).contains { $0.isImage } }
        let projector = hasImages ? VisionDownload.installedURL(storage: storage) : nil
        if hasImages && (!VisionDownload.supports(model) || projector == nil) {
            error = "This conversation includes images. Select Qwen3.5 4B with image support, or start a new text-only chat."; save(); return
        }
        do {
            let files = try AttachmentStore(storage: storage)
            for turn in turns {
                var message = ["role": turn.role, "content": turn.content]
                for attachment in turn.attachments ?? [] {
                    if let text = attachment.text { message["content", default: ""] += "\n\nAttached file: \(attachment.name)\n\(text)" }
                    if attachment.isImage {
                        guard let url = files.imageURL(attachment), FileManager.default.fileExists(atPath: url.path) else { throw RiftFailure("A saved image is missing. Please attach it again in a new chat.") }
                        message["imageFile"] = url.path
                    }
                }
                messages.append(message)
            }
        } catch { self.error = error.localizedDescription; save(); return }
        conversations[index].messages.append(.init(id: replyID, role: "assistant", content: "", modelName: model.name))
        conversations[index].updatedAt = Date(); generating = true; stopping = false; generationID = operation; status = "Preparing model"
        UIApplication.shared.isIdleTimerDisabled = true; save()
        let context = max(512, min(8192, self.context)), maxTokens = max(1, min(2048, self.maxTokens))
        let working = catalog.first { $0.id == model.catalogID }?.workingGB
        inference.prepare()
        Task {
            var failure: String?
            do {
                let finalText = try await inference.run(model: model, url: storage.url(for: model), messages: messages, projector: projector, context: context, maxTokens: maxTokens, temperature: Float(temperature), thinking: thinking, workingGB: working, text: { [weak self] text in
                    Task { @MainActor in
                        guard let self, self.generationID == operation, let c = self.conversations.firstIndex(where: { $0.id == chatID }), let m = self.conversations[c].messages.firstIndex(where: { $0.id == replyID }) else { return }
                        self.conversations[c].messages[m].content = text; self.scheduleSave()
                    }
                }, status: { [weak self] status in
                    Task { @MainActor in guard let self, self.generationID == operation else { return }; self.status = status }
                })
                if let c = conversations.firstIndex(where: { $0.id == chatID }), let m = conversations[c].messages.firstIndex(where: { $0.id == replyID }), !finalText.isEmpty { conversations[c].messages[m].content = finalText }
            } catch { if !stopping { failure = error.localizedDescription; self.error = failure } }
            if let c = conversations.firstIndex(where: { $0.id == chatID }), let m = conversations[c].messages.firstIndex(where: { $0.id == replyID }) {
                conversations[c].messages[m].interrupted = stopping
                if let failure { conversations[c].messages[m].failureDescription = failure }
                if conversations[c].messages[m].content.isEmpty { conversations[c].messages[m].interrupted = true }
            }
            generationID = nil; generating = false; UIApplication.shared.isIdleTimerDisabled = false
            if stopping { status = "Stopped" } else if failure != nil { status = "Reply not started" }; refreshMemory(); save()
        }
    }
    func thermalChanged() { if generating && [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) { stop(); error = "Generation stopped to let your iPhone cool down." } }
    func lowMemory() { if generating { stop() }; inference.unload(); error = "iOS reported low memory. Rift released its model; a smaller model or context may help." }

    func download(_ item: CatalogModel) {
        guard item.uncensored, !busy, !generating, ready, let storage else { return }
        let destination = storage.transfers.appendingPathComponent(item.id + ".partial")
        let resumeURL = storage.transfers.appendingPathComponent(item.id + ".resume")
        let complete = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) == item.bytes } ?? false
        guard complete || storage.freeSpace() > item.bytes + 300 * 1_048_576 || FileManager.default.fileExists(atPath: resumeURL.path) else {
            error = "Free up \(item.sizeLabel) plus 300 MB of working space before downloading."; return
        }
        transferID = item.id; transferProgress = 0; transferStatus = "Preparing download"; pausedID = nil; error = nil
        transferTask = Task {
            await inference.release() // A previously loaded model must not coexist with a big transfer.
            refreshMemory()
            do {
                try Task.checkCancellation()
                if !complete {
                    let resume = try? Data(contentsOf: resumeURL)
                    let job = DownloadJob(destination: destination, expectedBytes: item.bytes)
                    downloader = job; transferStatus = "Downloading"
                    for try await event in job.start(url: item.downloadURL, cellular: cellular, resumeData: resume) {
                        switch event {
                        case .progress(let value): transferProgress = value
                        case .file: break
                        }
                    }
                }
                if pausedID == item.id { throw CancellationError() }
                transferStatus = "Verifying model"; transferProgress = 0
                let verification = Task.detached(priority: .utility) { [weak self] () throws -> InstalledModel in
                    let hash = try GGUFInspector.hash(destination) { value in
                        Task { @MainActor [weak self] in
                            guard self?.transferID == item.id, self?.transferStatus == "Verifying model" else { return }
                            self?.transferProgress = value
                        }
                    }
                    guard hash == item.sha256 else { throw RiftFailure("The download checksum did not match. The file was not installed. Tap Download to try again.") }
                    let info = try GGUFInspector.inspect(destination)
                    guard info.architecture == item.architecture else { throw RiftFailure("The downloaded architecture did not match the catalog.") }
                    try Task.checkCancellation()
                    let filename = item.id + ".gguf", final = storage.models.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: final.path) { throw RiftFailure("This model is already installed.") }
                    try FileManager.default.moveItem(at: destination, to: final)
                    return .init(id: item.id, name: item.name, filename: filename, bytes: item.bytes, sha256: hash, architecture: info.architecture, catalogID: item.id, importedAt: Date())
                }
                importTask = verification
                let installedModel = try await verification.value
                installed.append(installedModel); select(installedModel); save()
                try? FileManager.default.removeItem(at: resumeURL)
            } catch {
                let failure = error as NSError
                let cancelled = error is CancellationError || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
                if !cancelled && pausedID != item.id {
                    self.error = error.localizedDescription
                    if let data = failure.userInfo["NSURLSessionDownloadTaskResumeData"] as? Data, data.count < 2 * 1_048_576 {
                        try? data.write(to: resumeURL, options: .atomic); pausedID = item.id
                    } else { try? FileManager.default.removeItem(at: resumeURL) }
                    if !cancelled { try? FileManager.default.removeItem(at: destination) }
                }
            }
            transferID = nil; downloader = nil; importTask = nil; transferTask = nil; refreshMemory()
        }
    }
    func pauseDownload() {
        guard !pausing, let id = transferID, let job = downloader, let storage, transferStatus == "Downloading" else { return }
        let operation = UUID()
        pausedID = id; pausing = true; pauseOperation = operation
        Task {
            let data = await job.pause()
            guard pauseOperation == operation else { return }
            if let data { try? data.write(to: storage.transfers.appendingPathComponent(id + ".resume"), options: .atomic) }
            pausing = false; pauseOperation = nil
        }
    }
    func cancelTransfer() {
        transferTask?.cancel(); downloader?.cancel(); importTask?.cancel(); pausedID = nil; pauseOperation = nil; pausing = false
        if let id = transferID, let storage { try? FileManager.default.removeItem(at: storage.transfers.appendingPathComponent(id + ".resume")) }
    }
    func importModel(_ source: URL) {
        guard !busy, !generating, ready, let storage else { return }
        importing = true; transferStatus = "Reading model"; transferProgress = 0
        let task = Task.detached(priority: .utility) { () throws -> InstalledModel in
            let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let temporary = storage.transfers.appendingPathComponent(UUID().uuidString + ".partial")
            defer { try? FileManager.default.removeItem(at: temporary) }
            var coordinationError: NSError?, copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinated in
                do {
                    let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 24, Int64(size) + 700 * 1_048_576 < storage.freeSpace() else { throw RiftFailure("There is not enough free space to copy this model, or the file is incomplete.") }
                    try FileManager.default.copyItem(at: coordinated, to: temporary)
                } catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }; if let copyError { throw copyError }
            try Task.checkCancellation()
            let info = try GGUFInspector.inspect(temporary)
            let hash = try GGUFInspector.hash(temporary)
            let id = "custom-" + hash, filename = id + ".gguf", final = storage.models.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: final.path) { try FileManager.default.moveItem(at: temporary, to: final) }
            return .init(id: id, name: info.name, filename: filename, bytes: info.bytes, sha256: hash, architecture: info.architecture, catalogID: nil, importedAt: Date())
        }
        importTask = task
        Task {
            await inference.release()
            do {
                let item = try await task.value
                if !installed.contains(where: { $0.sha256 == item.sha256 }) { installed.append(item) }
                if let existing = installed.first(where: { $0.sha256 == item.sha256 }) { select(existing) }
                save()
            } catch { if !(error is CancellationError) { self.error = error.localizedDescription } }
            importing = false; importTask = nil
        }
    }
}
