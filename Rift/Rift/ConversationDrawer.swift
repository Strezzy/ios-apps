import SwiftUI

/// Kept independent of scroll and text-field gestures: only the screen edge or
/// the exposed foreground card receives the horizontal reveal gesture.
enum DrawerMotion {
    static func progress(open: Bool, translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return open ? 1 : 0 }
        return min(1, max(0, (open ? 1 : 0) + translation / width))
    }
    static func shouldOpen(open: Bool, projected: CGFloat, width: CGFloat) -> Bool {
        progress(open: open, translation: projected, width: width) > 0.5
    }
}

enum ComposerAction: Equatable {
    case voice, send, stop, close
    static func resolve(draft: String, voice: Bool, generating: Bool) -> Self {
        if voice { return .close }
        if generating { return .stop }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .voice : .send
    }
    var symbol: String {
        switch self { case .voice: "waveform"; case .send: "arrow.up"; case .stop: "stop.fill"; case .close: "xmark" }
    }
    var label: String {
        switch self { case .voice: "Voice mode"; case .send: "Send message"; case .stop: "Stop reply"; case .close: "Close voice mode" }
    }
    var identifier: String {
        switch self { case .voice: "openVoiceMode"; case .send: "sendMessage"; case .stop: "stopReply"; case .close: "closeVoiceMode" }
    }
}

struct ConversationDrawer: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    let onSelect: () -> Void
    let onSettings: () -> Void
    private var chats: [Conversation] {
        model.conversations.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                backdrop
                if chats.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Your conversations live here" : "No matches",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(search.isEmpty ? "Start a chat. It stays on this iPhone." : "Try another search."))
                } else {
                    List {
                        ForEach(chats) { chat in
                            Button { model.activeChatID = chat.id; onSelect() } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(chat.id == model.activeChatID ? Color(red: 0.6, green: 0.75, blue: 0.9) : .clear)
                                        .frame(width: 3)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(chat.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(chat.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.vertical, 8)
                            }
                            .listRowBackground(Color.white.opacity(chat.id == model.activeChatID ? 0.055 : 0))
                            .swipeActions {
                                Button(role: .destructive) { model.deleteChat(chat) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                ShareLink(item: chat.transcript) { Label("Export conversation", systemImage: "square.and.arrow.up") }
                                Button("Delete conversation", systemImage: "trash", role: .destructive) { model.deleteChat(chat) }
                            }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Conversations").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search conversations")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSelect) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Close conversations")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape").font(.system(size: 21, weight: .medium))
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Settings").accessibilityIdentifier("drawerSettings")
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .tint(Color(red: 0.72, green: 0.82, blue: 0.94))
        .environment(\.colorScheme, .dark)
    }
    private var backdrop: some View {
        LinearGradient(colors: [Color(red: 0.035, green: 0.045, blue: 0.065), Color(red: 0.09, green: 0.12, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Canvas { context, size in
                    var grid = Path()
                    for x in stride(from: 0.0, through: size.width, by: 28) {
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: 0.0, through: size.height, by: 28) {
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
            }
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
