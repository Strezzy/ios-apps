import SwiftUI

struct InteractiveCard: View {
    var image: UIImage?
    var depth: UIImage?
    var amount: Double
    var rarity: Rarity
    var serial: Int = 1
    var total: Int
    var sleeved: Bool
    var active = true
    @StateObject private var motion = CardMotion()
    @State private var drag = SIMD2<Float>.zero
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let tilt = reduceMotion ? SIMD2<Float>.zero : motion.tilt + drag
        CardFace(image: image,depth: depth,amount: amount,tilt: tilt,rarity: rarity,serial: serial,total: total,sleeved: sleeved,live: image != nil)
            .rotation3DEffect(.degrees(Double(tilt.y) * -7),axis: (x: 1,y: 0,z: 0),perspective: 0.5)
            .rotation3DEffect(.degrees(Double(tilt.x)*9),axis: (x: 0,y: 1,z: 0),perspective: 0.5)
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in drag = SIMD2(Float(max(-1,min(1,value.translation.width/140))),Float(max(-1,min(1,value.translation.height/140)))) }.onEnded { _ in withAnimation(.spring(response: 0.6,dampingFraction: 0.7)) { drag = .zero } })
            .onAppear { updateMotion() }.onDisappear { motion.stop() }
            .onChange(of: active) { _,_ in updateMotion() }.onChange(of: scenePhase) { _,_ in updateMotion() }.onChange(of: reduceMotion) { _,_ in updateMotion() }
            .accessibilityHint("Tilt your phone or drag gently to explore the card's depth.")
    }
    private func updateMotion() { if active && scenePhase == .active && !reduceMotion { motion.start() } else { motion.stop() } }
}

struct CreateView: View {
    @EnvironmentObject private var store: CollectionStore
    @ObservedObject var editor: EditorModel
    var active: Bool
    var onCreated: (CollectorCard) -> Void
    var onPalette: ([RGB]) -> Void
    @State private var showEdits = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 8) {
                        Text("A MOMENT. MADE RARE.").font(.system(size: 9,weight: .semibold,design: .monospaced)).tracking(3).foregroundStyle(.secondary)
                        Text(editor.image == nil ? "Make it collectible." : "Make it yours.").font(.system(size: 32,weight: .light,design: .serif))
                    }.padding(.top,12)
                    InteractiveCard(image: editor.image,depth: editor.depthEnabled ? editor.depth : nil,amount: editor.depthEnabled ? editor.depthAmount : 0,rarity: editor.rarity,total: editor.editionCount,sleeved: editor.sealing,active: active)
                        .frame(maxWidth: 255).padding(.horizontal,28)
                        .animation(.spring(response: 0.7,dampingFraction: 0.8),value: editor.sealing)
                    if let draft = store.draft {
                        draftRecovery(draft)
                    } else if editor.image == nil {
                        VStack(spacing: 14) {
                            Button(action: editor.pick) { Label(editor.working ? "Opening photo…" : "Choose a photo",systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical,8) }.buttonStyle(.glassProminent).disabled(editor.working)
                            Text("Give a photo depth. Choose its rarity.\nSeal it into a collection of its own.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    } else {
                        editingControls
                        Button { editor.showSeal = true } label: {
                            Label(editor.sealing ? "Sealing your edition…" : "Seal edition",systemImage: "seal").frame(maxWidth: .infinity).padding(.vertical,8)
                        }.buttonStyle(.glassProminent).disabled(!editor.canSeal)
                        Text("The original is removed from Photos before sealing.\nYour card stays safely in Collectr.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let error = editor.depthError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Try depth again") { editor.updateDepth() }.buttonStyle(.glass)
                    }
                }.padding(.horizontal,24).padding(.bottom,32).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .navigationTitle("Create").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editor.image != nil && store.draft == nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("Change",systemImage: "photo.on.rectangle",action: editor.pick).labelStyle(.iconOnly).accessibilityLabel("Choose another photo") }
                }
            }
            .toolbarBackground(.hidden,for: .navigationBar)
            .sheet(isPresented: $editor.showPicker) { LibraryPicker(onPick: editor.importPhoto,onError: { editor.error = $0 }) }
            .confirmationDialog("Seal this edition?",isPresented: $editor.showSeal,titleVisibility: .visible) {
                Button("Delete original & seal \(editor.editionCount) \(editor.editionCount == 1 ? "copy" : "copies")",role: .destructive) { Task { if let card = await editor.seal(store: store) { onCreated(card) } } }
            } message: { Text("Collectr saves your card first, then asks Photos to delete the original. iOS will ask you to confirm. Deleted photos remain in Recently Deleted until you remove them there. The edition size cannot be changed after sealing.") }
            .alert("Couldn’t finish",isPresented: Binding(get: { editor.error != nil },set: { if !$0 { editor.error = nil } })) { Button("OK") { editor.error = nil } } message: { Text(editor.error ?? "") }
            .onChange(of: editor.palette) { _,colors in onPalette(colors) }
        }
    }
    private var editingControls: some View {
        VStack(spacing: 16) {
            GlassPanel {
                VStack(spacing: 18) {
                    TextField("Name this moment",text: $editor.title).font(.headline).submitLabel(.done).onChange(of: editor.title) { _,v in if v.count > 80 { editor.title = String(v.prefix(80)) } }
                    Divider().overlay(.white.opacity(0.1))
                    HStack {
                        Toggle("Depth",isOn: $editor.depthEnabled).onChange(of: editor.depthEnabled) { _,_ in editor.updateDepth() }
                        if editor.depthWorking { ProgressView().controlSize(.small).accessibilityLabel("Adding depth") }
                    }
                    if editor.depthEnabled {
                        Slider(value: $editor.depthAmount,in: 0...1) { Text("Depth strength") }
                        HStack { Text("Subtle"); Spacer(); Text(editor.depthWorking ? "Adding depth…" : "Immersive") }.font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Rarity").font(.subheadline)
                        Spacer()
                        Picker("Rarity",selection: $editor.rarity) { ForEach(Rarity.allCases) { rarity in Label(rarity.title,systemImage: rarity.symbol).tag(rarity) } }.tint(editor.rarity.color)
                    }
                    HStack {
                        VStack(alignment: .leading,spacing: 4) { Text("Edition size").font(.subheadline); Text("\(editor.editionCount == 1 ? "One of a kind" : "\(editor.editionCount) numbered copies")").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        TextField("Copies",value: $editor.editionCount,format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 65)
                            .onChange(of: editor.editionCount) { _,n in editor.editionCount = min(1000,max(1,n)) }
                        Stepper("Copies",value: $editor.editionCount,in: 1...1000).labelsHidden().fixedSize()
                    }
                }
            }
            DisclosureGroup("Light, color & framing",isExpanded: $showEdits) {
                VStack(spacing: 16) {
                    editSlider("Light",value: $editor.edits.exposure,range: -1...1)
                    editSlider("Color",value: $editor.edits.saturation,range: 0...1.8)
                    editSlider("Warmth",value: $editor.edits.warmth,range: -1...1)
                    editSlider("Frame horizontally",value: $editor.edits.cropX,range: 0...1)
                    editSlider("Frame vertically",value: $editor.edits.cropY,range: 0...1)
                    Text("Photos fill a gently rounded 5:7 card.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,16)
            }.font(.subheadline).tint(.white).padding(.horizontal,6)
        }
    }
    private func editSlider(_ title: String,value: Binding<Double>,range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading,spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Slider(value: value,in: range,onEditingChanged: { editing in if !editing { editor.scheduleRender() } }) { Text(title) } }
    }
    private func draftRecovery(_ draft: DraftRecord) -> some View {
        GlassPanel {
            VStack(spacing: 14) {
                Text("Your edition is saved.").font(.headline)
                Text(draft.deletionConfirmed ? "Finish sealing to add it to Collections." : "Continue the Photos confirmation to seal your edition.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Continue sealing") { Task { if let card = await editor.resume(store: store) { editor.reset(); onCreated(card) } } }.buttonStyle(.glassProminent).disabled(editor.sealing)
                if !draft.deletionConfirmed { Button("Discard draft",role: .destructive) { do { try store.discardDraft() } catch { editor.error = error.localizedDescription } }.buttonStyle(.glass) }
            }
        }
    }
}
