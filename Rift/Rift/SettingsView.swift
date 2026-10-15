import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search=""
    var chats: [Conversation] { model.conversations.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains(where:{$0.content.localizedCaseInsensitiveContains(search)}) }.sorted {$0.updatedAt > $1.updatedAt} }
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                if chats.isEmpty { ContentUnavailableView(search.isEmpty ? "Your conversations live here" : "No matches",systemImage:"bubble.left.and.bubble.right",description:Text(search.isEmpty ? "Start a chat. It stays on this iPhone." : "Try another search.")) }
                else {
                    List { ForEach(chats) { chat in
                        Button { model.activeChatID=chat.id; dismiss() } label: { VStack(alignment:.leading,spacing:6) { Text(chat.title).font(.headline).foregroundStyle(.primary).lineLimit(2); Text(chat.updatedAt,style:.date).font(.caption).foregroundStyle(.secondary) }.padding(.vertical,6) }
                            .listRowBackground(Color.clear)
                            .swipeActions { Button(role:.destructive) { model.deleteChat(chat) } label: { Label("Delete",systemImage:"trash") } }
                            .contextMenu { ShareLink(item:chat.transcript) { Label("Export conversation",systemImage:"square.and.arrow.up") }; Button("Delete conversation",systemImage:"trash",role:.destructive) { model.deleteChat(chat) } }
                    } }.scrollContentBackground(.hidden)
                }
            }.navigationTitle("Conversations").searchable(text:$search,prompt:"Search on this iPhone")
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Done") { dismiss() } }; ToolbarItem(placement:.topBarTrailing) { Button { model.newChat(); dismiss() } label: { Image(systemName:"square.and.pencil") }.disabled(model.generating).accessibilityLabel("New chat") } }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var clearConfirmation=false
    @State private var animationPreview=false
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                Form {
                    Section {
                        HStack(spacing:16) { RiftMark().frame(width:44,height:56); VStack(alignment:.leading,spacing:4) { Text("Rift").font(.system(.title2,design:.rounded,weight:.bold)); Text("Private AI. On your terms.").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical,8)
                    }.listRowBackground(Color.clear)
                    Section("Privacy") {
                        Label("Always on-device", systemImage: "lock.fill").accessibilityIdentifier("privacyAlwaysLocal")
                        Text("Chat and voice transcription run on this iPhone. Internet is used for model or speech-language downloads you request, never to generate replies.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("Allow cellular model downloads", isOn: $model.cellular)
                        Text("No account, analytics, cloud inference, or automatic chat uploads. Chats and models are excluded from app-managed iCloud backup. Exporting a chat or choosing a cloud file in Files is your action.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Voice") {
                        NavigationLink("Voice & sound") { VoiceSettingsView(model: model) }
                            .accessibilityIdentifier("voiceSettingsLink")
                    }
                    Section("Reply animation") {
                        ReplyStylePicker()
                        ReplyAnimationSample()
                        Button("Larger preview", systemImage: "arrow.up.left.and.arrow.down.right") { animationPreview = true }
                        Text("Choose quiet effects or expressive Starlight, Wave and Bubble. Reduce Motion removes particles and movement. Low Power Mode uses a lighter fade.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Conversation") {
                        Picker("Context",selection:$model.context) { Text("512 · minimum").tag(512); Text("1K · low memory").tag(1024); Text("2K · lighter").tag(2048); Text("4K · balanced").tag(4096); Text("8K · more memory").tag(8192) }.disabled(model.generating)
                        Picker("Reply length",selection:$model.maxTokens) { Text("Shorter").tag(512); Text("Standard").tag(1024); Text("Longer").tag(2048) }.disabled(model.generating)
                        Toggle("Allow model thinking",isOn:$model.thinking).disabled(model.generating)
                        VStack(alignment:.leading) { HStack { Text("Creativity"); Spacer(); Text(model.temperature,format:.number.precision(.fractionLength(1))).foregroundStyle(.secondary) }; Slider(value:$model.temperature,in:0.1...1.4,step:0.1) }.disabled(model.generating)
                        Text("Rift automatically lowers context when needed, down to 512 tokens, without changing models. Thinking and longer context use more memory and time. Old turns are left out when the context fills; saved chats are not deleted.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Assistant instructions") {
                        TextEditor(text:$model.systemPrompt).frame(minHeight:90).disabled(model.generating)
                        Button("Restore default instructions") { model.systemPrompt="You are Rift, a helpful local assistant. Answer clearly." }.disabled(model.generating)
                    }
                    Section("This iPhone") {
                        LabeledContent("Device",value:model.device.name)
                        LabeledContent("Physical memory",value:"\(model.device.ram) GB")
                        LabeledContent("Remaining app memory", value: MemoryBudget.label(model.memorySnapshot.remaining))
                            .accessibilityIdentifier("memoryRemaining")
                        LabeledContent("In use by app / host", value: MemoryBudget.label(model.memorySnapshot.footprint))
                        LabeledContent("Estimated process budget", value: model.memorySnapshot.estimatedBudget.map(MemoryBudget.label) ?? "Unavailable")
                            .accessibilityIdentifier("memoryBudget")
                        Button("Unload model from memory") { Task { await model.releaseModelMemory() } }
                            .disabled(model.generating || model.busy)
                        Text("Remaining memory is what this process can allocate now, not its total limit. The budget estimate adds memory already in use. Readings refresh while this screen is open; iOS can change the allowance.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Why is the memory limit low?") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Rift requests Increased Memory Limit. Inside LiveContainer, the signed host process controls the allowance; Rift's guest entitlements cannot raise it.")
                                Text("To request more memory, enable Increased Memory Limit for the actual LiveContainer host's App ID in your signing setup, then reinstall or re-sign that same host without deleting its data. Standalone installations need the capability on Rift instead.")
                                Text("Extended Virtual Addressing expands address space, not physical RAM. A larger allowance is device- and profile-dependent, not guaranteed. This screen does not claim that a signing capability was granted merely because the IPA requests it.")
                            }.font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        LabeledContent("Downloaded models",value:"\(model.installed.count)")
                        Text("Device labels are for browsing. Actual available memory, context size, and thermal state determine whether a model can run. Physical iPhone and LiveContainer performance still need device testing.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("About uncensored models") {
                        Text("Every curated download is an explicitly uncensored community variant. Rift adds no content-filtering layer, refusal rewriting, or remote moderation request. A model can still refuse or make mistakes; no zero-refusal promise is made. Custom imports retain their own behavior.").font(.callout)
                        Text("The catalog was researched on October 14, 2026. Small Qwen3.5, Gemma 4, and LFM2.5 variants were selected for phone-scale memory budgets. Newer large desktop models are not automatically better phone choices.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Local data") {
                        Button("Delete all conversations",role:.destructive) { clearConfirmation=true }
                        Text("Downloaded models are managed in Models. Deleting a model does not delete your chats.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Credits") {
                        Text("Inference: llama.cpp and ggml (MIT), with their bundled chat-template runtime. Models retain their respective authors' licenses; see each download's source and license.").font(.caption)
                        Text("Rift 1.5 · Strezzy").font(.caption).foregroundStyle(.secondary)
                    }
                }.scrollContentBackground(.hidden)
            }.task {
                model.refreshMemory()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3)) } catch { break }
                    model.refreshMemory()
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $animationPreview) { ReplyAnimationPreview() }
                .confirmationDialog("Delete every conversation on this iPhone? This cannot be undone.",isPresented:$clearConfirmation,titleVisibility:.visible) { Button("Delete all conversations",role:.destructive) { model.clearChats() } }
        }
    }
}
