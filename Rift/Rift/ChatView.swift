import SwiftUI
import UIKit

enum RiftSheet: String, Identifiable { case models, history, settings; var id: String { rawValue } }
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft=""
    @State private var sheet: RiftSheet?
    @FocusState private var composing: Bool
    @State private var followsBottom = true
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                if let startup=model.startupError { ContentUnavailableView("Local data unavailable",systemImage:"externaldrive.badge.exclamationmark",description:Text(startup)).padding() }
                else {
                    VStack(spacing:0) {
                        ErrorBanner()
                        if model.activeChat?.messages.isEmpty != false { welcome }
                        else { messages }
                    }.safeAreaInset(edge:.bottom,spacing:0) { composer }
                }
            }
            .navigationTitle("Rift").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button { sheet = .history } label: { Image(systemName:"line.3.horizontal").frame(width:28,height:28) }.accessibilityLabel("Chat history") }
                ToolbarItem(placement:.principal) {
                    Button { composing=false; sheet = .models } label: {
                        VStack(spacing:2) { Text("Rift").font(.headline).foregroundStyle(.primary); HStack(spacing:4) { Text(model.selectedModel?.name ?? "Choose a model").lineLimit(1); Image(systemName:"chevron.down").font(.system(size:8,weight:.bold)) }.font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).accessibilityIdentifier("modelPicker")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { model.newChat(); draft="" } label: { Image(systemName:"square.and.pencil") }.disabled(model.generating).accessibilityLabel("New chat")
                    Menu { Button("Models",systemImage:"cpu") { sheet = .models }; Button("Settings",systemImage:"slider.horizontal.3") { sheet = .settings } } label: { Image(systemName:"ellipsis") }.accessibilityLabel("More options")
                }
            }
            .sheet(item:$sheet) { choice in
                switch choice { case .models: ModelLibraryView(); case .history: HistoryView(); case .settings: SettingsView() }
            }
        }
    }
    private var welcome: some View {
        VStack(spacing:18) {
            Spacer(minLength:28)
            RiftMark().frame(width:84,height:102)
            VStack(spacing:8) { Text("A little space to think.").font(.system(.title2,design:.rounded,weight:.semibold)); Text("Your conversations. Your iPhone.").font(.subheadline).foregroundStyle(.secondary) }
            if model.selectedModel == nil {
                Button { sheet = .models } label: { Label("Choose your AI",systemImage:"sparkle").font(.headline).padding(.horizontal,20).padding(.vertical,10) }.buttonStyle(.glassProminent).padding(.top,10)
                Text("Download once. Chat offline.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing:9) {
                    suggestion("Help me think something through",icon:"sparkles")
                    suggestion("Explain something simply",icon:"lightbulb")
                    suggestion("Write something with me",icon:"pencil.line")
                }.padding(.top,16).frame(maxWidth:320)
            }
            Spacer(minLength:40)
        }.padding(.horizontal,28).frame(maxWidth:.infinity)
    }
    private func suggestion(_ text: String, icon: String) -> some View {
        Button { draft=text; composing=true } label: { HStack { Image(systemName:icon).frame(width:22).foregroundStyle(RiftTheme.accent); Text(text).font(.callout); Spacer(); Image(systemName:"arrow.up.left").font(.caption).foregroundStyle(.tertiary) }.padding(14) }.buttonStyle(.plain).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
    }
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:22) {
                    ForEach(model.activeChat?.messages ?? []) { message in MessageView(message:message,isStreaming:model.generating && message.id == model.activeChat?.messages.last?.id).id(message.id) }
                    Color.clear.frame(height:1).id("bottom")
                }.padding(.horizontal,20).padding(.vertical,20)
            }.scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 100
                } action: { _, value in followsBottom = value }
                .onChange(of:model.activeChat?.messages.last?.content) { _, _ in if followsBottom { withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo("bottom",anchor:.bottom) } } }
                .onChange(of:model.activeChatID) { _, _ in proxy.scrollTo("bottom",anchor:.bottom) }
                .onAppear { proxy.scrollTo("bottom",anchor:.bottom) }
        }
    }
    private var composer: some View {
        VStack(spacing:8) {
            HStack(alignment:.bottom,spacing:10) {
                TextField("Message",text:$draft,axis:.vertical).lineLimit(1...5).focused($composing).padding(.vertical,11).padding(.leading,18).submitLabel(.send).onSubmit(send).accessibilityIdentifier("messageInput")
                if model.generating {
                    Button { model.stop() } label: { Image(systemName:"stop.fill").font(.system(size:14,weight:.bold)).frame(width:42,height:42) }.buttonStyle(.glassProminent).accessibilityLabel("Stop reply")
                } else {
                    Button(action:send) { Image(systemName:"arrow.up").font(.system(size:18,weight:.semibold)).frame(width:42,height:42) }.buttonStyle(.glassProminent).disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.selectedModel == nil).accessibilityLabel("Send message")
                }
            }.padding(7).glassEffect(.regular,in:RoundedRectangle(cornerRadius:29))
            HStack(spacing:5) {
                Image(systemName:model.generating ? "sparkle" : "lock.fill").font(.system(size:8))
                Text(model.generating ? model.status : "On-device AI · Responses can be inaccurate").font(.system(size:10))
            }.foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
        }.padding(.horizontal,16).padding(.top,8).padding(.bottom,8)
    }
    private func send() { guard !model.generating, model.selectedModel != nil else { return }; let text=draft; draft=""; composing=false; model.send(text) }
}
struct MessageView: View {
    @EnvironmentObject var model: AppModel
    let message: ChatMessage
    let isStreaming: Bool
    var body: some View {
        let user=message.role == "user", parts=ReplyParts.parse(message.content)
        HStack(alignment:.top) {
            if user { Spacer(minLength:35) }
            VStack(alignment:.leading,spacing:10) {
                if !user { HStack(spacing:7) { Image(systemName:"sparkle").foregroundStyle(RiftTheme.accent); Text(message.modelName ?? "Rift").foregroundStyle(.secondary) }.font(.caption.weight(.medium)) }
                if !parts.thought.isEmpty {
                    DisclosureGroup(isStreaming && parts.answer.isEmpty ? "Thinking" : "Thought process") { Text(parts.thought).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.font(.caption).tint(RiftTheme.accent)
                }
                if !parts.answer.isEmpty || isStreaming { MarkdownMessage(text:parts.answer, isStreaming:isStreaming, interrupted:message.interrupted) }
                if isStreaming && message.content.isEmpty { HStack(spacing:9) { ProgressView().controlSize(.small); Text(model.status).font(.callout).foregroundStyle(.secondary) } }
                if !user && !isStreaming {
                    HStack(spacing:18) {
                        Button { UIPasteboard.general.string=message.content } label: { Image(systemName:"document.on.document") }.accessibilityLabel("Copy reply")
                        if message.id == model.activeChat?.messages.last?.id { Button { model.regenerate() } label: { Image(systemName:"arrow.clockwise") }.disabled(model.generating).accessibilityLabel("Regenerate reply") }
                        if message.interrupted { Text("Interrupted").font(.caption2) }
                    }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                }
            }.padding(user ? 14 : 0).background { if user { RoundedRectangle(cornerRadius:22).fill(RiftTheme.accent.opacity(0.11)) } }
            if !user { Spacer(minLength:0) }
        }.contextMenu { Button("Copy",systemImage:"document.on.document") { UIPasteboard.general.string=message.content } }
    }
}
struct MarkdownMessage: View {
    let text: String
    var isStreaming = false
    var interrupted = false
    var body: some View {
        let chunks = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                if index % 2 == 0 {
                    StreamingText(text: chunk, isStreaming: isStreaming, interrupted: interrupted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(chunk.components(separatedBy: "\n").first ?? "Code").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = chunk.components(separatedBy: "\n").dropFirst().joined(separator: "\n") } label: { Image(systemName: "document.on.document") }.accessibilityLabel("Copy code")
                        }
                        ScrollView(.horizontal) {
                            StreamingText(text: chunk.components(separatedBy: "\n").dropFirst().joined(separator: "\n"), isStreaming: isStreaming, interrupted: interrupted, monospaced: true)
                        }
                    }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}
