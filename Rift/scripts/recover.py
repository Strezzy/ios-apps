#!/usr/bin/env python3
"""One-time, idempotent recovery of the interrupted source snapshot."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def edit(name,changes):
    path=ROOT/name
    text=path.read_text()
    for old,new in changes: text=text.replace(old,new)
    path.write_text(text)
# Apply the original initialization corrections once, then stop mutating source at build time.
p=ROOT/'scripts/prepare.py'; t=p.read_text()
a=t.index('def source_corrections():'); b=t.index("if __name__=='__main__':",a)
t=t[:a]+'def source_corrections():\n    pass\n'+t[b:]
t=t.replace("info.get('cardData',{}).get('license','See model source')","(info.get('cardData') or {}).get('license') or 'See model source'")
p.write_text(t)
edit('Rift/Models.swift',[
 ('var system = utsname(); uname(&system)','var system = utsname(); uname(&system)\n        let capacity = MemoryLayout.size(ofValue: system.machine)'),
 ('capacity: MemoryLayout.size(ofValue: system.machine)','capacity: capacity')
] if 'let capacity =' not in (ROOT/'Rift/Models.swift').read_text() else [])
edit('Rift/AppModel.swift',[
 ('    let storage: LocalStorage?','    private(set) var storage: LocalStorage?'),
 ('let store=try LocalStorage(root:storageOverride); storage=store','let store=try LocalStorage(root:storageOverride)'),
 ('activeChatID=conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id\n        } catch','activeChatID=conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id\n            storage=store\n        } catch'),
 ('private var stopping=false','private var stopping=false\n    private let diskQueue = DispatchQueue(label: "com.billy.rift.persistence", qos: .utility)'),
 ('do { try storage.write(conversations,name:"chats.json"); try storage.write(installed,name:"models.json") }\n        catch { self.error="Could not save local data: \\(error.localizedDescription)" }','let chats = conversations, models = installed\n        diskQueue.async { [weak self] in\n            do { try storage.write(chats,name:"chats.json"); try storage.write(models,name:"models.json") }\n            catch { let message = error.localizedDescription; Task { @MainActor in self?.error = "Could not save local data: " + message } }\n        }'),
 ('try await inference.run(model:model','let finalText = try await inference.run(model:model'),
 ('})\n            } catch { if !stopping','})\n                if let c = conversations.firstIndex(where: { $0.id == chatID }), let m = conversations[c].messages.firstIndex(where: { $0.id == replyID }), !finalText.isEmpty { conversations[c].messages[m].content = finalText }\n            } catch { if !stopping'),
 ('generating=false; UIApplication.shared.isIdleTimerDisabled=false','generationID=nil; generating=false; UIApplication.shared.isIdleTimerDisabled=false'),
 ('guard model.uncensored, !busy, !offline, let storage','guard model.uncensored, !busy, !generating, !offline, let storage'),
 ('guard !busy, let storage else { return }','guard !busy, !generating, let storage else { return }')
])
p=ROOT/'Rift/AppModel.swift'; t=p.read_text(); a=t.index('final class InferenceService:'); b=t.index('@MainActor final class AppModel:',a)
service='''final class InferenceService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.billy.rift.inference", qos: .userInitiated)
    private let engine = RiftEngine()
    private var loadedID: String?
    private var loadedContext = 0
    func stop() { engine.cancel() }
    func unload() {
        engine.cancel()
        queue.async { self.engine.unload(); self.loadedID = nil; self.loadedContext = 0 }
    }
    func run(model: InstalledModel, url: URL, messages: [[String:String]], context: Int, maxTokens: Int, temperature: Float, thinking: Bool, workingGB: Double?, text: @escaping @Sendable (String)->Void, status: @escaping @Sendable (String)->Void) async throws -> String {
        engine.resetCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.loadedID != model.id || self.loadedContext != context { self.engine.unload(); self.loadedID = nil }
                    let required = self.loadedID == model.id ? UInt64(256 * 1_048_576) : MemoryBudget.required(bytes: model.bytes, context: context, workingGB: workingGB)
                    guard MemoryBudget.fits(required: required, available: RiftAvailableMemory()) else {
                        throw RiftFailure("Not enough memory is available. Close other apps, shorten context, or select a smaller model. Browsing another iPhone does not increase this phone's memory.")
                    }
                    #if targetEnvironment(simulator)
                    let cpu = true
                    #else
                    let cpu = false
                    #endif
                    var finalText = ""
                    _ = try self.engine.generate(atPath: url.path, messages: messages, context: Int32(context), maxTokens: Int32(maxTokens), temperature: temperature, thinking: thinking, cpu: cpu, token: { value in finalText = value; text(value) }, status: status)
                    self.loadedID = model.id; self.loadedContext = context
                    continuation.resume(returning: finalText)
                } catch {
                    self.loadedID = nil; self.loadedContext = 0
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

'''
t=t[:a]+service+t[b:]; p.write_text(t)
p=ROOT/'Rift/Native/RiftEngine.h'; t=p.read_text()
if '- (void)resetCancellation;' not in t: t=t.replace('- (void)cancel;','- (void)cancel;\n- (void)resetCancellation;')
p.write_text(t)
p=ROOT/'Rift/Native/RiftEngine.mm'; t=p.read_text().replace('    _cancelled.store(false);\n    llama_sampler','    llama_sampler')
if '- (void)resetCancellation {' not in t: t=t.replace('- (void)cancel {','- (void)resetCancellation { _cancelled.store(false); }\n- (void)cancel {')
t=t.replace('if(count<0) { piece.resize','if(count < -1048576) throw std::runtime_error("Invalid tokenizer piece length.");\n            if(count<0) { piece.resize')
p.write_text(t)
p=ROOT/'Rift/ChatView.swift'; t=p.read_text()
if 'import UIKit' not in t: t=t.replace('import SwiftUI','import SwiftUI\nimport UIKit',1)
t=t.replace('Text(.init(chunk))','Text(LocalizedStringKey(chunk))')
t=t.replace('    @FocusState private var composing: Bool','    @FocusState private var composing: Bool\n    @State private var followsBottom = true') if 'var followsBottom' not in t else t
t=t.replace('}.scrollDismissesKeyboard(.interactively)','}.scrollDismissesKeyboard(.interactively)\n                .onScrollGeometryChange(for: Bool.self) { geometry in\n                    geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 100\n                } action: { _, value in followsBottom = value }') if '.onScrollGeometryChange' not in t else t
t=t.replace('.onChange(of:model.activeChat?.messages.last?.content) { _, _ in proxy.scrollTo("bottom",anchor:.bottom) }','.onChange(of:model.activeChat?.messages.last?.content) { _, _ in if followsBottom { withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo("bottom",anchor:.bottom) } } }')
t=t.replace('if !parts.answer.isEmpty { MarkdownMessage(text:parts.answer) }','if !parts.answer.isEmpty || isStreaming { MarkdownMessage(text:parts.answer, isStreaming:isStreaming, interrupted:message.interrupted) }')
a=t.index('struct MarkdownMessage: View {')
t=t[:a]+'''struct MarkdownMessage: View {
    let text: String
    var isStreaming = false
    var interrupted = false
    var body: some View {
        let chunks = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chunks.enumerated()), id: \\.offset) { index, chunk in
                if index % 2 == 0 {
                    StreamingText(text: chunk, isStreaming: isStreaming, interrupted: interrupted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(chunk.components(separatedBy: "\\n").first ?? "Code").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = chunk.components(separatedBy: "\\n").dropFirst().joined(separator: "\\n") } label: { Image(systemName: "document.on.document") }.accessibilityLabel("Copy code")
                        }
                        ScrollView(.horizontal) {
                            StreamingText(text: chunk.components(separatedBy: "\\n").dropFirst().joined(separator: "\\n"), isStreaming: isStreaming, interrupted: interrupted, monospaced: true)
                        }
                    }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}
'''
p.write_text(t)
p=ROOT/'Rift/SettingsView.swift'; t=p.read_text()
if '@State private var animationPreview' not in t:
    t=t.replace('@State private var clearConfirmation=false','@State private var clearConfirmation=false\n    @State private var animationPreview=false\n    @AppStorage("rift.replyAnimation") private var replyAnimation="bloom"')
    t=t.replace('Section("Conversation") {','Section("Reply animation") {\n                        Picker("Style", selection: $replyAnimation) { Text("Bloom").tag("bloom"); Text("Soft fade").tag("fade"); Text("Instant").tag("instant") }\n                        Button("Preview animation", systemImage: "sparkles") { animationPreview=true }\n                        Text("New letters softly appear and settle into place. Reduce Motion removes the lift, scale and blur. Low Power Mode uses a lighter fade.").font(.caption).foregroundStyle(.secondary)\n                    }\n                    Section("Conversation") {')
    t=t.replace('.confirmationDialog("Delete every conversation', '.sheet(isPresented: $animationPreview) { ReplyAnimationPreview() }\n                .confirmationDialog("Delete every conversation')
p.write_text(t)
p=ROOT/'Rift/Theme.swift'; t=p.read_text().replace('.font(.system(size:10,weight:.semibold,design:.rounded))','.font(.system(.caption2, design:.rounded, weight:.semibold))'); p.write_text(t)
p=ROOT/'Rift/ModelLibraryView.swift'; t=p.read_text().replace('.disabled(model.busy || model.offline)', '.disabled(model.busy || model.generating || model.offline)').replace('.disabled(model.busy)', '.disabled(model.busy || model.generating)'); p.write_text(t)
# Record completion so subsequent native builds do not rewrite source.
(ROOT/'RECOVERY-APPLIED').write_text('Recovered source and integrated native Bloom rendering.\n')
print('Recovered and integrated Rift source.')
