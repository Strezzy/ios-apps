import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profileID=DeviceProfile.current.id
    @State private var expanded: Set<String>=["Qwen"]
    @State private var showImporter=false
    @State private var pendingDownload: CatalogModel?
    @State private var deleting: InstalledModel?
    var profile: DeviceProfile { DeviceProfile.profiles.first {$0.id == profileID} ?? model.device }
    var models: [CatalogModel] { profile.models(from:model.catalog) }
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        ErrorBanner().padding(.horizontal,-20)
                        VStack(alignment:.leading,spacing:10) {
                            Text("Choose your AI").font(.system(.largeTitle,design:.rounded,weight:.bold))
                            Text("A few good models. All yours.").foregroundStyle(.secondary)
                        }.padding(.top,8)
                        deviceCard
                        if model.busy { transferCard }
                        if !model.installed.isEmpty {
                            VStack(alignment:.leading,spacing:12) {
                                sectionLabel("ON YOUR IPHONE")
                                ForEach(model.installed) { installed in
                                    HStack(spacing:12) {
                                        Image(systemName:installed.id == model.selectedModelID ? "checkmark.circle.fill" : "cpu").foregroundStyle(RiftTheme.accent).frame(width:26)
                                        VStack(alignment:.leading,spacing:4) { Text(installed.name).font(.subheadline.weight(.semibold)); Text(installed.isCustom ? "Imported · uncensored status unverified" : "Ready offline").font(.caption).foregroundStyle(.secondary) }
                                        Spacer(minLength:0)
                                        Menu { Button("Use model",systemImage:"checkmark") { model.select(installed); dismiss() }; Button("Delete download",systemImage:"trash",role:.destructive) { deleting=installed } } label: { Image(systemName:"ellipsis").frame(width:40,height:40) }.disabled(model.generating).accessibilityLabel("Manage \(installed.name)")
                                    }.padding(14).background(.thinMaterial,in:RoundedRectangle(cornerRadius:20))
                                }
                            }
                        }
                        VStack(alignment:.leading,spacing:12) {
                            sectionLabel("CURATED FOR \(profile.name.uppercased())")
                            ForEach(["Qwen","Gemma","Liquid"],id:\.self) { family in
                                let entries=models.filter {$0.family == family}
                                if !entries.isEmpty { familyCard(family,entries:entries) }
                            }
                        }
                        Button { showImporter=true } label: { HStack(spacing:14) { Image(systemName:"folder.badge.plus").font(.title3); VStack(alignment:.leading,spacing:4) { Text("Import your own model").font(.subheadline.weight(.semibold)); Text("Choose a compatible GGUF in Files").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"plus") }.padding(18) }.buttonStyle(.plain).background(.thinMaterial,in:RoundedRectangle(cornerRadius:22)).disabled(model.busy).accessibilityIdentifier("importModel")
                        Text("Curated downloads are publisher-labeled uncensored variants, not stock models. Refusal behavior can still vary. Device fits are estimates until tested on a physical iPhone; live memory checks always apply.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                        if model.offline { Label("Offline mode is on. Imports and installed models still work.",systemImage:"wifi.slash").font(.caption).foregroundStyle(.secondary) }
                    }.padding(20)
                }
            }.navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Done") { dismiss() } }; ToolbarItem(placement:.topBarTrailing) { Button { showImporter=true } label: { Image(systemName:"plus") }.disabled(model.busy).accessibilityLabel("Import model from Files") } }
                .fileImporter(isPresented:$showImporter,allowedContentTypes:[UTType(filenameExtension:"gguf") ?? .data],allowsMultipleSelection:false) { result in do { if let url=try result.get().first { model.importModel(url) } } catch { model.error=error.localizedDescription } }
                .sheet(item:$pendingDownload) { item in DownloadConsentView(item:item) { model.download(item) } }
                .confirmationDialog("Delete downloaded model? Your chats will stay on this iPhone.",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) { if let deleting { Button("Delete \(deleting.name)",role:.destructive) { model.deleteModel(deleting); self.deleting=nil } } }
        }
    }
    private var deviceCard: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                Image(systemName:"iphone").font(.title2).foregroundStyle(RiftTheme.accent)
                VStack(alignment:.leading,spacing:3) {
                    Picker("iPhone",selection:$profileID) { ForEach(DeviceProfile.profiles) { item in Text(item.name).tag(item.id) } }.pickerStyle(.menu).labelsHidden().padding(.leading,-12)
                    Text(profileID == model.device.id ? "Detected · \(model.device.ram) GB RAM" : "Browsing another iPhone · estimated \(profile.ram) GB RAM").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
            }
            if profileID != model.device.id { Text("Downloads still have to fit your actual iPhone.").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).glassEffect(.regular.tint(RiftTheme.accent.opacity(0.06)),in:RoundedRectangle(cornerRadius:24))
    }
    private var transferCard: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(model.transferStatus).font(.subheadline.weight(.semibold)); Spacer(); if model.transferStatus == "Downloading" { Button { model.pauseDownload() } label: { Image(systemName:"pause.fill") }.accessibilityLabel("Pause download") }; Button { model.cancelTransfer() } label: { Image(systemName:"xmark") }.accessibilityLabel("Cancel transfer") }
            if model.importing { ProgressView().controlSize(.small) } else { ProgressView(value:model.transferProgress) }
        }.padding(18).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
    }
    private func familyCard(_ family: String, entries: [CatalogModel]) -> some View {
        VStack(alignment:.leading,spacing:0) {
            Button {
                withAnimation(.snappy(duration:0.22)) { if expanded.contains(family) { expanded.remove(family) } else { expanded.insert(family) } }
            } label: {
                HStack(spacing:12) {
                    Text(String(family.prefix(1))).font(.system(.headline,design:.rounded,weight:.bold)).frame(width:36,height:36).background(RiftTheme.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
                    VStack(alignment:.leading,spacing:3) { Text(family).font(.headline); Text(family == "Qwen" ? "Uncensored Aggressive" : family == "Gemma" ? "Uncensored Aggressive" : "Heretic · uncensored").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Text("\(entries.count)").font(.caption).foregroundStyle(.secondary); Image(systemName:expanded.contains(family) ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.padding(16).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("family-\(family)")
            if expanded.contains(family) {
                ForEach(entries) { item in
                    Divider().padding(.horizontal,16)
                    VStack(alignment:.leading,spacing:10) {
                        HStack(alignment:.top,spacing:8) { Text(item.name).font(.subheadline.weight(.semibold)); Spacer(minLength:4); BenefitBadge(text:item.badge) }
                        HStack(alignment:.center,spacing:10) {
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                            if let installed=model.installed.first(where:{$0.catalogID==item.id}) {
                                Button { model.select(installed); dismiss() } label: { Image(systemName:installed.id == model.selectedModelID ? "checkmark" : "arrow.right").frame(width:36,height:36) }.buttonStyle(.glass).disabled(model.generating).accessibilityLabel("Use \(item.name)")
                            } else {
                                Button { pendingDownload=item } label: { Image(systemName:model.pausedID == item.id ? "play.fill" : "arrow.down").frame(width:36,height:36) }.buttonStyle(.glass).disabled(model.busy || model.offline).accessibilityLabel("Download \(item.name)")
                            }
                        }
                        HStack(spacing:6) { Text(item.sizeLabel); Text("·"); Text("\(item.variant)"); if item.workingGB >= 6 { Text("· Higher memory") } }.font(.system(size:10)).foregroundStyle(.secondary)
                    }.padding(16)
                }
            }
        }.background(.thinMaterial,in:RoundedRectangle(cornerRadius:24)).overlay { RoundedRectangle(cornerRadius:24).strokeBorder(RiftTheme.accent.opacity(0.07),lineWidth:0.5) }
    }
    private func sectionLabel(_ value: String) -> some View { Text(value).font(.system(size:10,weight:.semibold)).tracking(1.4).foregroundStyle(.secondary) }
}
struct DownloadConsentView: View {
    let item: CatalogModel
    let accept: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                RiftBackground()
                ScrollView { VStack(alignment:.leading,spacing:20) {
                    Text(item.name).font(.system(.title,design:.rounded,weight:.bold)); BenefitBadge(text:item.badge)
                    Text(item.detail).foregroundStyle(.secondary)
                    LabeledContent("Download",value:item.sizeLabel)
                    LabeledContent("Format",value:"GGUF · \(item.variant)")
                    LabeledContent("License",value:item.license)
                    Text(item.licenseText).font(.callout).foregroundStyle(.secondary)
                    Text("The download connects to Hugging Face and its file-delivery hosts, which can see your IP address. Your messages are never part of that request. Once installed, chat works offline.").font(.callout).foregroundStyle(.secondary)
                    Text("This is an uncensored community modification. Its publisher's refusal and quality claims are not a guarantee. It can produce incorrect or unexpected content. Imported models are not certified as uncensored.").font(.caption).foregroundStyle(.secondary)
                    Link(destination:item.sourceURL) { Label("Model source and license",systemImage:"arrow.up.right.square") }
                    Button { dismiss(); accept() } label: { Text("Download \(item.sizeLabel)").font(.headline).frame(maxWidth:.infinity).padding(.vertical,12) }.buttonStyle(.glassProminent)
                }.padding(24) }
            }.navigationTitle("Download model").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarLeading) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.large])
    }
}
