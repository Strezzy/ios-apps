import SwiftUI
import UIKit

enum RiftSheet: String, Identifiable { case models, history, settings; var id: String { rawValue } }
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft=""
    @State private var sheet: RiftSheet?
    @FocusState private var composing: Bool
    @State private var following = ChatFollowingState()
    @State private var viewport = ChatViewport()
    @State private var bottomRequest = UUID()
    var body: some View {
        NavigationStack {
            ZStack {
                if let startup=model.startupError { ContentUnavailableView("Local data unavailable",systemImage:"externaldrive.badge.exclamationmark",description:Text(startup)).padding() }
                else {
                    VStack(spacing:0) {
                        ErrorBanner()
                        if model.activeChat?.messages.isEmpty != false { ScrollView { welcome }.scrollDismissesKeyboard(.interactively) }
                        else { messages }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { RiftBackground() }
            .safeAreaInset(edge: .bottom, spacing: 0) { if model.startupError == nil { composer } }
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
            if !model.ready {
                ProgressView("Opening local library").font(.caption).padding(.top, 10)
            } else if model.selectedModel == nil {
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
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(model.activeChat?.messages ?? []) { message in
                        MessageView(message: message, isStreaming: model.generating && message.id == model.activeChat?.messages.last?.id)
                            .id(message.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("chatMessage-\(message.id.uuidString)")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .accessibilityIdentifier("chatScrollView")
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .onScrollGeometryChange(for: ChatViewport.self) { geometry in
                ChatViewport(height: Double(geometry.containerSize.height),
                    contentHeight: Double(geometry.contentSize.height),
                    bottomDistance: Double(max(0, geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y - geometry.containerSize.height)))
            } action: { old, new in
                viewport = new
                if following.observe(old: old, new: new) { bottomRequest = UUID() }
            }
            .onScrollPhaseChange { _, phase in
                following.interaction(phase == .tracking || phase == .interacting || phase == .decelerating, viewport: viewport)
            }
            .onChange(of: composing) { _, focused in
                if focused { followLatest() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                // Re-anchor after keyboard layout, including frame changes which
                // do not produce a focus-state transition.
                if following.followsLatest && !following.userScrolling { bottomRequest = UUID() }
            }
            .onChange(of: model.activeChat?.messages.last?.content) { _, _ in
                if following.followsLatest && !following.userScrolling { bottomRequest = UUID() }
            }
            .onChange(of: model.activeChat?.messages.last?.id) { _, _ in followLatest() }
            .onChange(of: model.activeChatID) { _, _ in followLatest() }
            .onAppear { followLatest() }
            .task(id: bottomRequest) {
                await Task.yield()
                guard !Task.isCancelled, following.followsLatest, !following.userScrolling else { return }
                // Keep the latest line above the composer; per-letter motion is
                // handled by the renderer, not by a long scroll on every token.
                withTransaction(Transaction(animation: nil)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !following.followsLatest {
                    Button { followLatest() } label: { Label("Latest reply", systemImage: "arrow.down").font(.caption).padding(6) }
                        .buttonStyle(.glass).padding(12).accessibilityIdentifier("jumpToLatest")
                }
            }
        }
    }
    private func followLatest() {
        following.followLatest()
        bottomRequest = UUID()
    }
    private var composer: some View {
        VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.body).lineLimit(1...4).focused($composing)
                    .padding(.leading, 14).padding(.vertical, 10)
                    .submitLabel(.send).onSubmit(send).accessibilityIdentifier("messageInput")
                Button {
                    if model.generating { model.stop() } else { send() }
                } label: {
                    Image(systemName: model.generating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(RiftTheme.accent, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(!model.generating && (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.selectedModel == nil || !model.ready || model.busy))
                    .accessibilityLabel(model.generating ? "Stop reply" : "Send message")
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain).accessibilityIdentifier("composerBar")
            if !composing || model.generating {
                Text(model.generating ? model.status : "On-device AI · Responses can be inaccurate")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 3)
    }
    private func send() {
        if model.send(draft) { draft = ""; followLatest() }
    }
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
                    if message.isFailedReply || (message.interrupted && message.content.isEmpty) {
                        Label(message.failureDescription == nil ? "Reply stopped" : "Reply not started", systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing:18) {
                        Button { UIPasteboard.general.string=message.content } label: { Image(systemName:"document.on.document") }.accessibilityLabel("Copy reply")
                        if message.id == model.activeChat?.messages.last?.id { Button { model.regenerate() } label: { Label(message.isFailedReply ? "Retry reply" : "Regenerate", systemImage:"arrow.clockwise") }.disabled(model.generating).accessibilityLabel("Regenerate reply") }
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
