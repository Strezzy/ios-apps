import SwiftUI
import MultipeerConnectivity

private struct TradeMessage: Codable {
    enum Kind: String, Codable { case offer, ready, commit, receipt, cancel }
    var version = 1
    var kind: Kind
    var id: UUID
    var payload: CardPayload?
}
struct NearbyCollector: Identifiable {
    var id: UUID
    var name: String
    var peer: MCPeerID
    var connected: Bool
}

@MainActor
final class NearbyTrade: NSObject, ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var peers: [NearbyCollector] = []
    @Published var error: String?
    private let store: CollectionStore
    private let localPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var identities: [MCPeerID: UUID] = [:]
    private var reconnect: Task<Void, Never>?
    init(store: CollectionStore) {
        self.store = store
        localPeer = MCPeerID(displayName: String(UIDevice.current.name.prefix(40)))
        super.init()
        session = MCSession(peer: localPeer,securityIdentity: nil,encryptionPreference: .required); session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: localPeer,discoveryInfo: ["id": store.identity.uuidString],serviceType: "collectr-card"); advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: localPeer,serviceType: "collectr-card"); browser.delegate = self
    }
    func start() {
        guard !enabled else { return }; enabled = true; error = nil
        advertiser.startAdvertisingPeer(); browser.startBrowsingForPeers()
        reconnect = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.enabled else { return }
                for peer in self.peers {
                    if peer.connected { self.reconcile(peer.peer) }
                    else { self.invite(peer.peer) }
                }
            }
        }
    }
    func stop() {
        enabled = false; reconnect?.cancel(); reconnect = nil
        advertiser.stopAdvertisingPeer(); browser.stopBrowsingForPeers(); session.disconnect(); peers = []; identities = [:]
    }
    func pairingCode(_ peer: UUID) -> String {
        let pair = [store.identity.uuidString,peer.uuidString].sorted().joined(separator: ":")
        return String(CollectionStore.hash(Data(pair.utf8)).prefix(6)).uppercased()
    }
    private func invite(_ peer: MCPeerID) {
        // One deterministic inviter avoids simultaneous invitation races.
        guard let id = identities[peer], store.identity.uuidString < id.uuidString else { return }
        browser.invitePeer(peer,to: session,withContext: Data(store.identity.uuidString.utf8),timeout: 12)
    }
    private func send(_ message: TradeMessage, to peer: MCPeerID) throws {
        guard session.connectedPeers.contains(peer) else { throw CollectrError.message("The other phone disconnected. Reconnect to finish this trade.") }
        try session.send(JSONEncoder().encode(message),toPeers: [peer],with: .reliable)
    }
    func offer(_ card: CollectorCard, to collector: NearbyCollector) {
        do {
            let transfer = try store.offer(card,to: collector.id)
            try send(TradeMessage(kind: .offer,id: transfer.id,payload: try store.payload(card)),to: collector.peer)
        } catch { self.error = error.localizedDescription }
    }
    func accept(_ transfer: Transfer) {
        do {
            try store.accept(transfer.id)
            if let peer = peers.first(where: { $0.id == transfer.peer && $0.connected }) { try send(TradeMessage(kind: .ready,id: transfer.id),to: peer.peer) }
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ transfer: Transfer) {
        do {
            try store.decline(transfer.id)
            if let peer = peers.first(where: { $0.id == transfer.peer && $0.connected }) { try send(TradeMessage(kind: .cancel,id: transfer.id),to: peer.peer) }
        } catch { self.error = error.localizedDescription }
    }
    private func reconcile(_ peer: MCPeerID) {
        guard let id = identities[peer] else { return }
        do {
            for transfer in store.transfers where transfer.peer == id {
                let kind: TradeMessage.Kind?
                if transfer.incoming {
                    kind = transfer.phase == .staged ? .ready : transfer.phase == .received ? .receipt : nil
                } else {
                    kind = transfer.phase == .offered ? .offer : transfer.phase == .committed ? .commit : nil
                }
                if let kind { try send(TradeMessage(kind: kind,id: transfer.id,payload: kind == .offer ? try store.payload(transfer.card) : nil),to: peer) }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func handle(_ message: TradeMessage, from peer: MCPeerID) {
        guard enabled, message.version == 1, let id = identities[peer] else { return }
        do {
            switch message.kind {
            case .offer:
                guard let payload = message.payload else { return }
                if let old = store.transfers.first(where: { $0.id == message.id }), old.phase == .declined {
                    try send(TradeMessage(kind: .cancel,id: message.id),to: peer); return
                }
                if !store.transfers.contains(where: { $0.id == message.id }) { try store.stage(payload,id: message.id,from: id) }
            case .ready:
                if store.transfers.contains(where: { $0.id == message.id && $0.peer == id && !$0.incoming && $0.phase == .declined }) { try send(TradeMessage(kind: .cancel,id: message.id),to: peer); return }
                try store.commitOutgoing(message.id,peer: id)
                try send(TradeMessage(kind: .commit,id: message.id),to: peer)
            case .commit:
                try store.receiveCommit(message.id,peer: id)
                try send(TradeMessage(kind: .receipt,id: message.id),to: peer)
            case .receipt: try store.acknowledge(message.id,peer: id)
            case .cancel: try store.cancelFromPeer(message.id,peer: id)
            }
        } catch { self.error = error.localizedDescription }
    }
}

extension NearbyTrade: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String:String]?) {
        guard let raw = info?["id"], let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            guard self.enabled, id != self.store.identity else { return }
            self.identities[peerID] = id
            if !self.peers.contains(where: { $0.id == id }) { self.peers.append(NearbyCollector(id: id,name: peerID.displayName,peer: peerID,connected: false)) }
            self.invite(peerID)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.peers.removeAll { $0.peer == peerID && !$0.connected } }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.error = "Nearby access is unavailable. Check Local Network permission in Settings. \(error.localizedDescription)" }
    }
}
extension NearbyTrade: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didReceiveInvitationFromPeer peerID: MCPeerID,withContext context: Data?,invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let raw = context.flatMap { String(data: $0,encoding: .utf8) }
        Task { @MainActor in
            guard self.enabled, let raw, let id = UUID(uuidString: raw), id != self.store.identity else { invitationHandler(false,nil); return }
            self.identities[peerID] = id
            if !self.peers.contains(where: { $0.id == id }) { self.peers.append(NearbyCollector(id: id,name: peerID.displayName,peer: peerID,connected: false)) }
            invitationHandler(true,self.session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.error = "Nearby discovery could not start. \(error.localizedDescription)" }
    }
}
extension NearbyTrade: MCSessionDelegate {
    nonisolated func session(_ session: MCSession,peer peerID: MCPeerID,didChange state: MCSessionState) {
        Task { @MainActor in
            if let index = self.peers.firstIndex(where: { $0.peer == peerID }) { self.peers[index].connected = state == .connected }
            if state == .connected { self.reconcile(peerID) }
        }
    }
    nonisolated func session(_ session: MCSession,didReceive data: Data,fromPeer peerID: MCPeerID) {
        guard data.count < 20_000_000 else { return }
        do { let message = try JSONDecoder().decode(TradeMessage.self,from: data); Task { @MainActor in self.handle(message,from: peerID) } }
        catch { Task { @MainActor in self.error = "The incoming trade could not be read." } }
    }
    nonisolated func session(_ session: MCSession,didReceive stream: InputStream,withName streamName: String,fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession,didStartReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,with progress: Progress) {}
    nonisolated func session(_ session: MCSession,didFinishReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,at localURL: URL?,withError error: Error?) {}
}
