import Foundation
import SwiftUI
import UIKit

final class InferenceService: @unchecked Sendable {
    private let queue=DispatchQueue(label:"com.billy.rift.inference",qos:.userInitiated)
    private let engine=RiftEngine()
    private var loadedID: String?
    private var loadedContext=0
    func stop() { engine.cancel() }
    func unload() { engine.cancel(); queue.async { self.engine.unload(); self.loadedID=nil; self.loadedContext=0 } }
    func run(model: InstalledModel, url: URL, messages: [[String:String]], context: Int, maxTokens: Int, temperature: Float, thinking: Bool, workingGB: Double?, text: @escaping @Sendable (String)->Void, status: @escaping @Sendable (String)->Void) async throws -> String {
        engine.resetCancellation()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String,Error>) in
            queue.async {
                do {
                    if self.loadedID != model.id || self.loadedContext != context { self.engine.unload(); self.loadedID=nil }
                    let required=self.loadedID == model.id ? UInt64(256*1_048_576) : MemoryBudget.required(bytes:model.bytes,context:context,workingGB:workingGB)
                    guard MemoryBudget.fits(required:required,available:RiftAvailableMemory()) else { throw RiftFailure("Not enough memory is available right now. Close other apps, use a shorter context, or select a smaller model. Browsing another iPhone profile does not increase this phone's memory.") }
                    #if targetEnvironment(simulator)
                    let cpu=true
                    #else
                    let cpu=false
                    #endif
                    var finalText = ""
                    _ = try self.engine.generate(atPath:url.path,messages:messages,context:Int32(context),maxTokens:Int32(maxTokens),temperature:temperature,thinking:thinking,cpu:cpu,token:{ value in finalText=value; text(value) },status:status)
                    self.loadedID=model.id; self.loadedContext=context
                    continuation.resume(returning:finalText)
                } catch { self.loadedID=nil; self.loadedContext=0; continuation.resume(throwing:error) }
            }
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var catalog: [CatalogModel] = []
    @Published var installed: [InstalledModel] = []
    @Published var conversations: [Conversation] = []
    @Published var activeChatID: UUID?
    @Published var selectedModelID: String?
    @Published var error: String?
    @Published var startupError: String?
    @Published var generating=false
    @Published var status="On device"
    @Published var transferID: String?
    @Published var transferProgress: Double=0
    @Published var transferStatus=""
    @Published var pausedID: String?
    @Published var importing=false
    @AppStorage("rift.context") var context=2048
    @AppStorage("rift.maxTokens") var maxTokens=1024
    @AppStorage("rift.temperature") var temperature=0.7
    @AppStorage("rift.thinking") var thinking=false
    @AppStorage("rift.animateReplies") var animateReplies=true
    @AppStorage("rift.offline") var offline=false
    @AppStorage("rift.cellular") var cellular=false
    @AppStorage("rift.systemPrompt") var systemPrompt="You are Rift, a helpful local assistant. Answer clearly."
    private(set) var storage: LocalStorage?
    let device=DeviceProfile.current
    private let inference=InferenceService()
    private var downloader: DownloadJob?
    private var transferTask: Task<Void,Never>?
    private var importTask: Task<InstalledModel,Error>?
    private var saveTask: Task<Void,Never>?
    private var generationID: UUID?
    private var stopping=false
    var selectedModel: InstalledModel? { installed.first { $0.id == selectedModelID } }
    var activeChat: Conversation? { conversations.first { $0.id == activeChatID } }
    var busy: Bool { transferID != nil || importing }

    init(storageOverride: URL? = nil) {
        do {
            let store=try LocalStorage(root:storageOverride)
            storage=store
            guard let url=Bundle.main.url(forResource:"catalog",withExtension:"json") else { throw RiftFailure("The bundled model catalog is missing.") }
            catalog=try JSONDecoder().decode([CatalogModel].self,from:Data(contentsOf:url))
            guard !catalog.isEmpty, catalog.allSatisfy({$0.uncensored && $0.sha256.count == 64 && $0.revision.count == 40 && $0.bytes > 0}) else { throw RiftFailure("The bundled catalog did not pass validation.") }
            installed=try store.read("models.json",fallback:[InstalledModel]()).filter { FileManager.default.fileExists(atPath:store.url(for:$0).path) }
            conversations=try store.read("chats.json",fallback:[Conversation]())
            selectedModelID=UserDefaults.standard.string(forKey:"rift.selectedModel")
            if selectedModel == nil { selectedModelID=installed.first?.id }
            activeChatID=conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id
        } catch {
            storage=nil; startupError="Rift could not open its local data. Existing files have been left untouched. \(error.localizedDescription)"
        }
    }
    func dismissError() { error=nil }
    private func save() {
        guard let storage, startupError == nil else { return }
        do { try storage.write(conversations,name:"chats.json"); try storage.write(installed,name:"models.json") }
        catch { self.error="Could not save local data: \(error.localizedDescription)" }
    }
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask=Task { try? await Task.sleep(for:.seconds(1)); self.saveTask=nil; self.save() }
    }
    func newChat() { guard !generating else { return }; activeChatID=nil; status="On device" }
    func select(_ model: InstalledModel) {
        guard !generating else { return }
        inference.unload(); selectedModelID=model.id
        UserDefaults.standard.set(model.id,forKey:"rift.selectedModel")
    }
    func deleteModel(_ model: InstalledModel) {
        guard !generating, let storage else { return }
        inference.unload()
        do {
            try FileManager.default.removeItem(at:storage.url(for:model))
            installed.removeAll {$0.id == model.id}
            if selectedModelID == model.id { selectedModelID=installed.first?.id; UserDefaults.standard.set(selectedModelID,forKey:"rift.selectedModel") }
            save()
        } catch { self.error=error.localizedDescription }
    }
    func deleteChat(_ chat: Conversation) {
        if generating && activeChatID == chat.id { stop() }
        conversations.removeAll {$0.id == chat.id}
        if activeChatID == chat.id { activeChatID=nil }
        save()
    }
    func clearChats() { stop(); conversations=[]; activeChatID=nil; save() }
    func stop() { stopping=true; inference.stop(); status="Stopping" }
    func background() { if generating { stop() }; inference.unload(); save(); UIApplication.shared.isIdleTimerDisabled=false }
    func send(_ draft: String) {
        let text=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, !generating, selectedModel != nil, startupError == nil else { return }
        guard text.utf8.count <= 100_000 else { error="This message is too long. Use a shorter message."; return }
        if activeChatID == nil { let chat=Conversation(); conversations.append(chat); activeChatID=chat.id }
        guard let index=conversations.firstIndex(where:{$0.id == activeChatID}) else { return }
        if conversations[index].messages.isEmpty { conversations[index].title=String(text.prefix(60)) }
        conversations[index].messages.append(.init(role:"user",content:text))
        beginReply()
    }
    func regenerate() {
        guard !generating, let index=conversations.firstIndex(where:{$0.id == activeChatID}), let last=conversations[index].messages.last, last.role == "assistant" else { return }
        conversations[index].messages.removeLast(); beginReply()
    }
    private func beginReply() {
        guard let model=selectedModel, let storage, let index=conversations.firstIndex(where:{$0.id == activeChatID}) else { return }
        guard ProcessInfo.processInfo.thermalState != .critical && ProcessInfo.processInfo.thermalState != .serious else { error="Your iPhone needs to cool down before generating another reply."; save(); return }
        let chatID=conversations[index].id, replyID=UUID(), operation=UUID()
        var messages=[[String:String]]()
        if !systemPrompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { messages.append(["role":"system","content":String(systemPrompt.prefix(8000))]) }
        messages += conversations[index].messages.filter { !$0.content.isEmpty }.map {["role":$0.role,"content":$0.content]}
        conversations[index].messages.append(.init(id:replyID,role:"assistant",content:"",modelName:model.name))
        conversations[index].updatedAt=Date(); generating=true; stopping=false; generationID=operation; status="Preparing model"
        UIApplication.shared.isIdleTimerDisabled=true; save()
        let context=max(512,min(8192,self.context)), maxTokens=max(1,min(2048,self.maxTokens))
        let working=catalog.first {$0.id == model.catalogID}?.workingGB
        Task {
            do {
                let finalText = try await inference.run(model:model,url:storage.url(for:model),messages:messages,context:context,maxTokens:maxTokens,temperature:Float(temperature),thinking:thinking,workingGB:working,text:{ [weak self] text in
                    Task { @MainActor in
                        guard let self, self.generationID == operation, let c=self.conversations.firstIndex(where:{$0.id==chatID}), let m=self.conversations[c].messages.firstIndex(where:{$0.id==replyID}) else { return }
                        self.conversations[c].messages[m].content=text; self.scheduleSave()
                    }
                },status:{ [weak self] status in
                    Task { @MainActor in guard let self, self.generationID == operation else { return }; self.status=status }
                })
                if let c=conversations.firstIndex(where:{$0.id==chatID}), let m=conversations[c].messages.firstIndex(where:{$0.id==replyID}) { conversations[c].messages[m].content=finalText }
            } catch { if !stopping { self.error=error.localizedDescription } }
            generationID=nil
            if let c=conversations.firstIndex(where:{$0.id==chatID}), let m=conversations[c].messages.firstIndex(where:{$0.id==replyID}) {
                conversations[c].messages[m].interrupted=stopping
                if conversations[c].messages[m].content.isEmpty { conversations[c].messages[m].content=stopping ? "Reply stopped." : "No reply was generated. Try again or choose another model."; conversations[c].messages[m].interrupted=true }
            }
            generating=false; UIApplication.shared.isIdleTimerDisabled=false
            if stopping { status="Stopped" }; save()
        }
    }
    func thermalChanged() { if generating && [.serious,.critical].contains(ProcessInfo.processInfo.thermalState) { stop(); error="Generation paused to let your iPhone cool down." } }
    func lowMemory() { if generating { stop() }; inference.unload(); error="iOS reported low memory. Rift released its model; a smaller model or context may help." }

    func download(_ model: CatalogModel) {
        guard model.uncensored, !busy, !offline, let storage else { return }
        guard storage.freeSpace() > model.bytes + 700*1_048_576 else { error="Free up \(model.sizeLabel) plus some working space before downloading this model."; return }
        let destination=storage.transfers.appendingPathComponent(model.id+".partial")
        let resumeURL=storage.transfers.appendingPathComponent(model.id+".resume")
        let resume=try? Data(contentsOf:resumeURL)
        let job=DownloadJob(destination:destination,expectedBytes:model.bytes)
        downloader=job; transferID=model.id; pausedID=nil; transferProgress=0; transferStatus="Downloading"
        transferTask=Task {
            do {
                for try await event in job.start(url:model.downloadURL,cellular:cellular,resumeData:resume) {
                    switch event {
                    case .progress(let value): transferProgress=value
                    case .file(let url):
                        transferStatus="Verifying model"; transferProgress=1
                        let verify=Task.detached(priority:.utility) { () throws -> InstalledModel in
                            let hash=try GGUFInspector.hash(url)
                            guard hash == model.sha256 else { throw RiftFailure("The SHA-256 checksum did not match. The model was not installed.") }
                            let info=try GGUFInspector.inspect(url)
                            guard info.architecture == model.architecture else { throw RiftFailure("The downloaded model architecture did not match the catalog.") }
                            let filename=model.id+".gguf", final=storage.models.appendingPathComponent(filename)
                            if FileManager.default.fileExists(atPath:final.path) { throw RiftFailure("This model is already installed.") }
                            try FileManager.default.moveItem(at:url,to:final)
                            return .init(id:model.id,name:model.name,filename:filename,bytes:model.bytes,sha256:hash,architecture:info.architecture,catalogID:model.id,importedAt:Date())
                        }
                        importTask=verify
                        let item=try await verify.value; installed.append(item); select(item); save()
                        try? FileManager.default.removeItem(at:resumeURL)
                    }
                }
            } catch {
                if pausedID != model.id && !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled { self.error=error.localizedDescription }
                if resume != nil && (error as NSError).domain == NSURLErrorDomain && (error as NSError).code != NSURLErrorCancelled { try? FileManager.default.removeItem(at:resumeURL); self.error="The saved download could not resume. Tap Download to restart it." }
                try? FileManager.default.removeItem(at:destination)
            }
            transferID=nil; downloader=nil; importTask=nil; transferTask=nil
        }
    }
    func pauseDownload() {
        guard let id=transferID, let job=downloader, let storage, transferStatus == "Downloading" else { return }
        pausedID=id
        Task { if let data=await job.pause() { try? data.write(to:storage.transfers.appendingPathComponent(id+".resume"),options:.atomic) } }
    }
    func cancelTransfer() {
        downloader?.cancel(); importTask?.cancel(); pausedID=nil
        if let id=transferID, let storage { try? FileManager.default.removeItem(at:storage.transfers.appendingPathComponent(id+".resume")) }
    }
    func importModel(_ source: URL) {
        guard !busy, let storage else { return }
        importing=true; transferStatus="Reading model"; transferProgress=0
        let task=Task.detached(priority:.utility) { () throws -> InstalledModel in
            let scoped=source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let temporary=storage.transfers.appendingPathComponent(UUID().uuidString+".partial")
            defer { try? FileManager.default.removeItem(at:temporary) }
            var coordinationError: NSError?, copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt:source,options:[],error:&coordinationError) { coordinated in
                do {
                    let size=try coordinated.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                    guard size > 24, Int64(size)+700*1_048_576 < storage.freeSpace() else { throw RiftFailure("There is not enough free space to copy this model, or the file is incomplete.") }
                    try FileManager.default.copyItem(at:coordinated,to:temporary)
                } catch { copyError=error }
            }
            if let coordinationError { throw coordinationError }; if let copyError { throw copyError }
            try Task.checkCancellation()
            let info=try GGUFInspector.inspect(temporary)
            let hash=try GGUFInspector.hash(temporary)
            let id="custom-"+hash, filename=id+".gguf", final=storage.models.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath:final.path) { try FileManager.default.moveItem(at:temporary,to:final) }
            return .init(id:id,name:info.name,filename:filename,bytes:info.bytes,sha256:hash,architecture:info.architecture,catalogID:nil,importedAt:Date())
        }
        importTask=task
        Task {
            do { let item=try await task.value; if !installed.contains(where:{$0.sha256==item.sha256}) { installed.append(item) }; if let existing=installed.first(where:{$0.sha256==item.sha256}) { select(existing) }; save() }
            catch { if !(error is CancellationError) { self.error=error.localizedDescription } }
            importing=false; importTask=nil
        }
    }
}
