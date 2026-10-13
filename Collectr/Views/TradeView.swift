import SwiftUI

struct TradeView: View {
    @EnvironmentObject private var store: CollectionStore
    @ObservedObject var nearby: NearbyTrade
    @Binding var selectedCard: UUID?
    @State private var selectedPeer: UUID?
    @State private var confirmOffer = false
    private var available: [CollectorCard] { store.cards.filter { !store.isLocked($0) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 24) {
                    VStack(alignment: .leading,spacing: 8) {
                        Text("LET IT FIND ITS NEXT HOME").font(.system(size: 9,weight: .semibold,design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text("Trade").font(.system(size: 35,weight: .light,design: .serif))
                        Text("A new owner. The same numbered card.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top,12)
                    GlassPanel {
                        VStack(alignment: .leading,spacing: 16) {
                            HStack {
                                Image(systemName: "iphone.radiowaves.left.and.right").font(.title2).symbolEffect(.pulse,isActive: nearby.enabled)
                                VStack(alignment: .leading,spacing: 4) { Text(nearby.enabled ? "Looking nearby" : "Meet another collector").font(.headline); Text("Open Trade on both phones.").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                            Button(nearby.enabled ? "Stop nearby" : "Find nearby collectors",action: { nearby.enabled ? nearby.stop() : nearby.start() }).buttonStyle(.glassProminent)
                            if nearby.enabled && nearby.peers.isEmpty { Text("Keep both phones unlocked with Wi-Fi and Bluetooth on.").font(.caption).foregroundStyle(.secondary) }
                            ForEach(nearby.peers) { peer in
                                Button { selectedPeer = peer.id } label: {
                                    HStack {
                                        Image(systemName: selectedPeer == peer.id ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading,spacing: 4) {
                                            Text(peer.name).font(.subheadline)
                                            Text(peer.connected ? "Pair code \(nearby.pairingCode(peer.id))" : "Connecting…").font(.caption.monospaced()).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Circle().fill(peer.connected ? .green : .orange).frame(width: 6,height: 6)
                                    }
                                }.buttonStyle(.plain).disabled(!peer.connected)
                            }
                        }
                    }
                    if !available.isEmpty {
                        GlassPanel {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Your copy").font(.subheadline)
                                    Spacer()
                                    Picker("Choose copy",selection: $selectedCard) {
                                        Text("Choose a card").tag(Optional<UUID>.none)
                                        ForEach(available) { card in Text("\(card.title) · \(card.serial)/\(card.editionSize)").tag(Optional(card.id)) }
                                    }.tint(.white)
                                }
                                if let card = available.first(where: { $0.id == selectedCard }) {
                                    CardFace(image: store.image(card,thumbnail: true),rarity: card.rarity,serial: card.serial,total: card.editionSize).frame(width: 160).padding(.vertical,8)
                                    Button("Offer this copy",systemImage: "arrow.up.forward") { confirmOffer = true }.buttonStyle(.glassProminent).disabled(!nearby.peers.contains(where: { $0.id == selectedPeer && $0.connected }))
                                }
                            }
                        }
                    } else if store.cards.isEmpty {
                        Text("Create a card or receive one to start your collection.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical,20)
                    }
                    if !store.transfers.isEmpty {
                        Text("THE STORY CONTINUES").font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        ForEach(store.transfers.prefix(12)) { transfer in transferRow(transfer) }
                    }
                    Text("Check the matching pair code on both screens. Each transfer moves one numbered copy. Its rarity, edition size and trade history travel with it.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).padding(.bottom,32).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.navigationBarTitleDisplayMode(.inline).toolbarBackground(.hidden,for: .navigationBar)
            .confirmationDialog("Offer this numbered copy?",isPresented: $confirmOffer,titleVisibility: .visible) {
                Button("Send offer") {
                    if let card = available.first(where: { $0.id == selectedCard }), let peer = nearby.peers.first(where: { $0.id == selectedPeer }) { nearby.offer(card,to: peer) }
                }
            } message: { Text("The other collector must accept. Once accepted, this copy leaves your collection and moves to theirs. To swap cards, each collector offers a copy in turn.") }
            .alert("Trade update",isPresented: Binding(get: { nearby.error != nil },set: { if !$0 { nearby.error = nil } })) { Button("OK") { nearby.error = nil } } message: { Text(nearby.error ?? "") }
        }
    }
    private func transferRow(_ transfer: Transfer) -> some View {
        GlassPanel {
            VStack(alignment: .leading,spacing: 12) {
                HStack {
                    Image(systemName: transfer.incoming ? "arrow.down.left" : "arrow.up.right")
                    VStack(alignment: .leading,spacing: 4) {
                        Text(transfer.card.title).font(.subheadline.weight(.medium))
                        Text("\(transfer.card.stamp) · \(status(transfer))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if [.received,.finished].contains(transfer.phase) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                }
                if transfer.phase == .offered {
                    HStack {
                        if transfer.incoming { Button("Accept card") { nearby.accept(transfer) }.buttonStyle(.glassProminent) }
                        Button(transfer.incoming ? "Decline" : "Cancel offer",role: .cancel) { nearby.cancel(transfer) }.buttonStyle(.glass)
                    }
                }
                if transfer.phase == .staged || transfer.phase == .committed {
                    Text("Keep both phones on Trade. If disconnected, reconnect the same phones to finish safely.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func status(_ t: Transfer) -> String {
        switch t.phase {
        case .offered: t.incoming ? "Waiting for you" : "Offer sent"
        case .staged: "Accepted · waiting for sender"
        case .committed: "Transferring · reconnect to finish"
        case .received: "Added to Collections"
        case .finished: "Trade complete"
        case .declined: "Cancelled"
        }
    }
}
