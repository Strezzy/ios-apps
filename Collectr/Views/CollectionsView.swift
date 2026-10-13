import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var store: CollectionStore
    var focused: CollectorCard?
    var namespace: Namespace.ID
    var onOpen: (CollectorCard) -> Void
    var onCreate: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,spacing: 25) {
                    VStack(alignment: .leading,spacing: 8) {
                        Text("THE THINGS YOU KEEP").font(.system(size: 9,weight: .semibold,design: .monospaced)).tracking(2.5).foregroundStyle(.secondary)
                        Text("Collections").font(.system(size: 35,weight: .light,design: .serif))
                        Text("\(store.groups.count) \(store.groups.count == 1 ? "edition" : "editions") · \(store.cards.count) \(store.cards.count == 1 ? "copy" : "copies")").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,12)
                    if store.cards.isEmpty {
                        VStack(spacing: 22) {
                            CardFace(image: nil).frame(width: 210).rotationEffect(.degrees(-5)).padding(.vertical,20)
                            Text("Start with something\nworth keeping.").font(.system(size: 27,weight: .light,design: .serif)).multilineTextAlignment(.center)
                            Button("Create your first card",action: onCreate).buttonStyle(.glassProminent)
                        }.frame(maxWidth: .infinity).padding(.vertical,20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(),spacing: 20),GridItem(.flexible(),spacing: 20)],spacing: 28) {
                            ForEach(store.groups,id: \.first!.editionID) { group in
                                let card = group[0]
                                Button { onOpen(card) } label: {
                                    VStack(alignment: .leading,spacing: 12) {
                                        if focused?.editionID != card.editionID {
                                            CardFace(image: store.image(card,thumbnail: true),rarity: card.rarity,serial: card.serial,total: card.editionSize)
                                                .matchedGeometryEffect(id: card.editionID,in: namespace)
                                        } else { Color.clear.aspectRatio(5/7,contentMode: .fit) }
                                        Text(card.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                        HStack { Text(card.rarity.title).foregroundStyle(card.rarity.color); Spacer(); Text("×\(group.count)").monospacedDigit() }.font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("\(card.title), \(group.count) copies. Inspect card.")
                            }
                        }
                    }
                }.padding(24).padding(.bottom,30).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.navigationBarTitleDisplayMode(.inline).toolbarBackground(.hidden,for: .navigationBar)
        }
    }
}

struct CardInspector: View {
    @EnvironmentObject private var store: CollectionStore
    var initial: CollectorCard
    var namespace: Namespace.ID
    var onClose: () -> Void
    var onTrade: (CollectorCard) -> Void
    @State private var card: CollectorCard?
    @State private var image: UIImage?
    @State private var depth: UIImage?
    @State private var sleeved = true
    @State private var flipped = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: CollectorCard { card ?? initial }
    private var copies: [CollectorCard] { store.cards.filter { $0.editionID == initial.editionID }.sorted { $0.serial < $1.serial } }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 18) {
                HStack {
                    Button("Close",systemImage: "xmark",action: onClose).labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                    Spacer()
                    Text("COLLECTR").font(.system(size: 10,weight: .medium,design: .monospaced)).tracking(4).foregroundStyle(.secondary)
                    Spacer()
                    Button("Flip",systemImage: "arrow.trianglehead.2.clockwise.rotate.90") { withAnimation(.spring(response: 0.7,dampingFraction: 0.85)) { flipped.toggle() } }.labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                }
                Spacer(minLength: 0)
                ZStack {
                    InteractiveCard(image: image,depth: depth,amount: selected.depthAmount,rarity: selected.rarity,serial: selected.serial,total: selected.editionSize,sleeved: sleeved,active: !flipped)
                        .opacity(flipped ? 0 : 1).rotation3DEffect(.degrees(flipped ? -180 : 0),axis: (x: 0,y: 1,z: 0))
                    certificate.opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(flipped ? 0 : 180),axis: (x: 0,y: 1,z: 0))
                }
                .frame(width: min(geo.size.width-48,(geo.size.height-260)*5/7,420))
                .matchedGeometryEffect(id: initial.editionID,in: namespace)
                .rotation3DEffect(.degrees(appeared || reduceMotion ? 0 : -35),axis: (x: 0,y: 1,z: 0))
                Spacer(minLength: 0)
                VStack(spacing: 7) {
                    Text(selected.title).font(.system(size: 27,weight: .light,design: .serif)).lineLimit(2).multilineTextAlignment(.center)
                    Text("\(selected.rarity.title.uppercased())   ·   \(selected.serial) OF \(selected.editionSize)").font(.system(size: 10,weight: .medium,design: .monospaced)).tracking(2).foregroundStyle(selected.rarity.color)
                }
                HStack(spacing: 12) {
                    Button(sleeved ? "Remove sleeve" : "Put in sleeve",systemImage: sleeved ? "rectangle.portrait.and.arrow.forward" : "rectangle.portrait") { withAnimation(.spring(response: 0.5,dampingFraction: 0.8)) { sleeved.toggle() } }.buttonStyle(.glass)
                    Menu {
                        ForEach(copies) { copy in Button("Copy \(copy.serial) of \(copy.editionSize)") { card = copy } }
                    } label: { Label("\(selected.serial)/\(selected.editionSize)",systemImage: "square.stack") }.buttonStyle(.glass).disabled(copies.count < 2)
                    Button("Trade",systemImage: "arrow.left.arrow.right") { onTrade(selected) }.labelStyle(.iconOnly).buttonStyle(.glassProminent).disabled(store.isLocked(selected))
                }.controlSize(.regular)
                Text(selected.depthAmount > 0 ? "Tilt gently to look inside." : "A moment, beautifully kept.").font(.caption2).foregroundStyle(.secondary).padding(.bottom,10)
            }.padding(.horizontal,24).padding(.top,8)
        }.onAppear {
            image = store.image(initial); depth = store.depthImage(initial.editionID)
            withAnimation(reduceMotion ? nil : .spring(response: 0.8,dampingFraction: 0.8)) { appeared = true }
        }
    }
    private var certificate: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: selected.rarity.symbol).font(.system(size: 40,weight: .ultraLight)).foregroundStyle(selected.rarity.color)
            Text("EDITION CERTIFICATE").font(.system(size: 9,weight: .medium,design: .monospaced)).tracking(2)
            Text("\(selected.serial)").font(.system(size: 64,weight: .ultraLight,design: .serif))
            Text("OF \(selected.editionSize)").font(.system(size: 11,design: .monospaced)).tracking(3).foregroundStyle(.secondary)
            Divider().padding(.horizontal,24)
            Text(selected.created,format: .dateTime.month(.wide).day().year()).font(.caption).foregroundStyle(.secondary)
            Text("\(selected.history.count) \(selected.history.count == 1 ? "trade" : "trades") in its story").font(.caption)
            if let last = selected.history.last { Text("Last traded \(last.date.formatted(date: .abbreviated,time: .omitted))").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Text(String(selected.editionID.uuidString.prefix(8)).uppercased()).font(.system(size: 9,design: .monospaced)).tracking(3).foregroundStyle(.tertiary).padding(.bottom,24)
        }.frame(maxWidth: .infinity).aspectRatio(5/7,contentMode: .fit).glassEffect(.regular,in: .rect(cornerRadius: 15))
    }
}
