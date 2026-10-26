import SwiftUI
import UniformTypeIdentifiers

struct CreativeToolsView:View {
    @EnvironmentObject private var store:LoopStore
    @Binding var project:LoopProject
    @ObservedObject var preview:EditorPreview
    @State private var cameraBusy=false
    @State private var cameraProgress=0.0
    @State private var cameraControl=ExportControl()
    @State private var choosing=false
    @State private var editID:UUID?
    @State private var importingLUT=false
    @State private var naming=false
    @State private var lookName=""
    @State private var saved=LookStorage.load()
    @State private var error:String?
    private var settings:EffectSettings{project.effects ?? EffectSettings()}
    private func change(_ update:(inout EffectSettings)->Void){var s=settings;update(&s);project.effects=s}
    private func scene<T>(_ path:WritableKeyPath<SceneSettings,T>)->Binding<T>{Binding(get:{(settings.scene ?? SceneSettings())[keyPath:path]},set:{v in change{var scene=$0.scene ?? SceneSettings();scene[keyPath:path]=v;$0.scene=scene}})}
    var body:some View {
        VStack(spacing:16){
            LoopCard {
                EditorSectionTitle(title:"Start with a look",subtitle:"One tap sets the mood. Every part stays editable.")
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:10){
                    ForEach(CinematicWorld.allCases){world in
                        Button{change{$0=world.apply(to:$0)}}label:{VStack(spacing:7){Image(systemName:world.symbol).font(.title3);Text(world.title).font(.caption.weight(.medium)).lineLimit(2)}.frame(maxWidth:.infinity,minHeight:66)}.buttonStyle(.glass).accessibilityIdentifier("world-\(world.id)")
                    }
                }
                if !saved.isEmpty {
                    Menu("My saved looks",systemImage:"heart") {ForEach(saved){look in Button(look.name){
                        let old=settings.scene?.subjects ?? [];let id=settings.scene?.selectedID
                        var value=look.effects;var scene=value.scene ?? SceneSettings();scene.subjects=old;scene.selectedID=id;value.scene=scene;project.effects=value
                    }}}
                }
                Button("Save this look",systemImage:"heart.badge.plus"){lookName="My look";naming=true}.font(.subheadline).buttonStyle(.glass)
            }
            LoopCard {
                HStack {Label("Who are we editing?",systemImage:"person.crop.rectangle").font(.headline);Spacer();Button{editID=nil;choosing=true}label:{Image(systemName:"plus.circle")}.accessibilityLabel("Choose a subject").disabled((settings.scene?.subjects.count ?? 0)>=3)}
                Picker("Apply new effects to",selection:scene(\.selectedID)) {
                    Text("Everyone / whole clip").tag(nil as UUID?)
                    ForEach(settings.scene?.subjects ?? []){subject in Text(subject.name).tag(Optional(subject.id))}
                }.pickerStyle(.menu)
                if let id=settings.scene?.selectedID,let subject=settings.scene?.subjects.first(where:{$0.id==id}) {
                    HStack {
                        Label(subject.path.isEmpty ? "Needs tracking":"Tracked subject",systemImage:subject.path.isEmpty ? "exclamationmark.circle":"checkmark.circle").font(.caption)
                        Spacer();Menu("Edit"){
                            Button("Repair selection"){editID=id;choosing=true}
                            Button("Remove subject",role:.destructive){change{$0.scene?.subjects.removeAll{$0.id==id};$0.scene?.selectedID=nil;$0.tracks?.removeAll{$0.subjectID==id}}}
                        }
                    }
                } else {Text("Choose a person or object to leave everything else alone.").font(.caption).foregroundStyle(.secondary)}
                DisclosureGroup("Depth & lighting") {
                    VStack(alignment:.leading,spacing:12){
                        Toggle("Use scene depth",isOn:scene(\.depthEnabled))
                        Text("Adds near-and-far separation for weather, focus and lighting. Requires extra processing.").font(.caption).foregroundStyle(.secondary)
                        if settings.scene?.depthEnabled==true {
                            labeled("Background focus blur",scene(\.depthBlur),0...1)
                            labeled("Focus distance",scene(\.focus),0...1)
                            labeled("Light strength",scene(\.relight),0...1)
                            labeled("Light warmth",scene(\.lightWarmth),-1...1)
                            labeled("Light direction",scene(\.lightDirection),-1...1)
                            labeled("Distant mist",scene(\.depthFog),0...1)
                            Toggle("Smooth depth in motion",isOn:scene(\.flowEnabled))
                            Button("Follow camera movement",systemImage:"viewfinder"){analyzeCamera()}.buttonStyle(.glass).disabled(cameraBusy)
                            if cameraBusy {ProgressView(value:cameraProgress);Button("Cancel"){cameraControl.cancel()}}
                            if !(settings.scene?.cameraKeys?.isEmpty ?? true){Text("Camera path ready").font(.caption);Button("Remove camera path"){change{$0.scene?.cameraKeys=nil}}}
                            Text("Analyzes 2D camera movement once to anchor weather. Best with a visible, steady background; this is not a 3D camera solve.").font(.caption2).foregroundStyle(.secondary)
                        }
                        labeled("Match subject to background",scene(\.matchLighting),0...1)
                        Toggle("Protect background while reshaping",isOn:scene(\.protectBackground))
                        if !(settings.scene?.subjects.isEmpty ?? true){Toggle("Precise subject edges",isOn:scene(\.preciseSelection))}
                        Text("Depth is an estimate, not a 3D scan. Background repair estimates newly exposed areas; it cannot recover hidden detail.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top,12)
                }.font(.subheadline).accessibilityIdentifier("sceneAdvanced")
            }
            DisclosureGroup("My effect mix · \(settings.visibleTracks.count)"){
                EffectMixView(project:$project,preview:preview)
            }.font(.subheadline.weight(.medium)).padding(.horizontal,4).accessibilityIdentifier("effectMixDisclosure")
            DisclosureGroup("Import a color look (.cube)"){
                VStack(alignment:.leading,spacing:10){
                    Text("Use a 3D LUT from Files. Color looks work offline after import.").font(.caption).foregroundStyle(.secondary)
                    Button("Choose .cube file",systemImage:"square.and.arrow.down"){importingLUT=true}.buttonStyle(.glass)
                    if let lut=settings.lut {
                        Text(lut.name).font(.subheadline)
                        Slider(value:Binding(get:{settings.lut?.amount ?? 1},set:{v in change{$0.lut?.amount=v}}),in:0...1)
                        Button("Remove imported look",role:.destructive){change{$0.lut=nil}}
                    }
                }.padding(.top,10)
            }.font(.subheadline).padding(.horizontal,4)
        }.sheet(isPresented:$choosing){SubjectPickerView(project:$project,preview:preview,editingID:editID)}
        .fileImporter(isPresented:$importingLUT,allowedContentTypes:[.data],allowsMultipleSelection:false){result in
            do {
                guard let url=try result.get().first else{return}
                let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
                guard url.pathExtension.lowercased()=="cube" else{throw LoopError.invalidSettings("Choose a .cube color lookup table.")}
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else{throw LoopError.invalidSettings("Choose a .cube file smaller than 20 MB.")}
                let lut=try CubeParser.parse(Data(contentsOf:url),name:url.deletingPathExtension().lastPathComponent);change{$0.lut=lut;$0.bypass=false}
            }catch{self.error=error.localizedDescription}
        }
        .alert("Save look",isPresented:$naming){
            TextField("Name",text:$lookName)
            Button("Cancel",role:.cancel){}
            Button("Save"){do{let name=lookName.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty else{return};saved.insert(SavedLook(name:String(name.prefix(60)),effects:LookStorage.portable(settings)),at:0);try LookStorage.save(saved)}catch{self.error=error.localizedDescription}}
        }
        .alert("Loop",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("OK",role:.cancel){}}message:{Text(error ?? "")}
    }
    private func analyzeCamera(){
        cameraBusy=true;cameraProgress=0;cameraControl=ExportControl()
        let snapshot=project,url=store.sourceURL(project),control=cameraControl
        Task {
            await preview.suspendForAnalysis()
            defer{cameraBusy=false;preview.resumeAfterAnalysis(project:project,url:url)}
            do{let keys=try await SceneCameraAnalyzer.analyze(url:url,project:snapshot,control:control){p in Task{@MainActor in cameraProgress=p}};change{if $0.scene==nil{$0.scene=SceneSettings()};$0.scene?.cameraKeys=keys}}
            catch{self.error=error.localizedDescription}
        }
    }
    private func labeled(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
        VStack(alignment:.leading,spacing:3){Text(title).font(.caption);Slider(value:value,in:range)}
    }
}

struct EffectMixView:View {
    @Binding var project:LoopProject
    @ObservedObject var preview:EditorPreview
    @State private var timingID:UUID?
    private var settings:EffectSettings{project.effects ?? EffectSettings()}
    private func change(_ update:(inout EffectSettings)->Void){var s=settings;s.moveLegacyToMix();update(&s);project.effects=s}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text("Effects run in order. Portrait shape is prepared before backgrounds and color. Tap the options button to change timing or target.").font(.caption).foregroundStyle(.secondary)
            if !settings.layers.isEmpty{Button("Edit existing effects as cards"){change{_ in}}.buttonStyle(.glass)}
            ForEach(settings.tracks ?? []){track in
                VStack(alignment:.leading,spacing:8){
                    HStack {
                        Button{edit(track.id){$0.enabled.toggle()}}label:{Image(systemName:track.enabled ? "checkmark.circle.fill":"circle")}.accessibilityLabel(track.enabled ? "Hide effect":"Show effect")
                        VStack(alignment:.leading){Text(EffectLibrary.preset(track.preset)?.name ?? "Effect").font(.subheadline.weight(.medium));Text(targetName(track)).font(.caption2).foregroundStyle(.secondary)}
                        Spacer();Menu {
                            Button("When it appears"){timingID=track.id}
                            Menu("Apply to"){
                                let category=EffectLibrary.preset(track.preset)?.category
                                Button(category == .background ? "Behind all people" : (category == .face || category == .body ? "All people" : "Whole clip")){edit(track.id){$0.subjectID=nil;$0.target="all"}}
                                if category != .face && category != .body && category != .background {
                                    Button("People"){edit(track.id){$0.subjectID=nil;$0.target="subject"}}
                                    Button("Background"){edit(track.id){$0.subjectID=nil;$0.target="background"}}
                                    if category == .looks || category == .lens {
                                        Button("Hair"){edit(track.id){$0.subjectID=nil;$0.target="hair"}}
                                        Button("Clothing"){edit(track.id){$0.subjectID=nil;$0.target="clothes"}}
                                    }
                                }
                                ForEach(settings.scene?.subjects ?? []){subject in Button(category == .background ? "Behind \(subject.name)" : subject.name){edit(track.id){$0.subjectID=subject.id;$0.target="subject"}}}
                            }
                            Button("Move earlier"){move(track.id,-1)};Button("Move later"){move(track.id,1)}
                            Button("Remove",role:.destructive){change{$0.tracks?.removeAll{$0.id==track.id}}}
                        }label:{Image(systemName:"ellipsis.circle").frame(width:36,height:36)}
                    }
                    Slider(value:Binding(get:{track.amount},set:{v in edit(track.id){$0.amount=v}}),in:0...1)
                }.padding(12).background(.thinMaterial,in:.rect(cornerRadius:16))
            }
            if (settings.tracks ?? []).isEmpty && settings.layers.isEmpty{Text("Pick an effect below to begin.").font(.caption).foregroundStyle(.secondary)}
        }.padding(.top,10)
        .sheet(isPresented:Binding(get:{timingID != nil},set:{if !$0{timingID=nil}})){
            if let id=timingID {timing(id)}
        }
    }
    private func targetName(_ t:EffectTrack)->String {
        let category=EffectLibrary.preset(t.preset)?.category
        if let id=t.subjectID {
            let name=settings.scene?.subjects.first{$0.id==id}?.name ?? "Missing subject"
            return category == .background ? "Behind \(name)" : name
        }
        if category == .background {return "Behind all people"}
        if category == .face || category == .body {return "All people"}
        switch t.target {case "all":return "Whole clip";case "subject":return "People";case "clothes":return "Clothing";default:return t.target.capitalized}
    }
    private func edit(_ id:UUID,_ update:(inout EffectTrack)->Void){change{if let i=$0.tracks?.firstIndex(where:{$0.id==id}){update(&$0.tracks![i])}}}
    private func move(_ id:UUID,_ delta:Int){change{guard let i=$0.tracks?.firstIndex(where:{$0.id==id}),let count=$0.tracks?.count,(0..<count).contains(i+delta) else{return};$0.tracks?.swapAt(i,i+delta)}}
    private func timing(_ id:UUID)->some View {
        NavigationStack {
            Form {
                if let track=settings.tracks?.first(where:{$0.id==id}) {
                    Section("Visible portion of the original clip"){
                        Text("Move the main playhead, then use Start here or End here. Times are source-video seconds.").font(.caption)
                        Button("Start here · \(LoopFormat.time(preview.displayedTime))"){edit(id){$0.start=preview.displayedTime;if ($0.end ?? project.trimEnd)<preview.displayedTime{$0.end=project.trimEnd}}}
                        Button("End here · \(LoopFormat.time(preview.displayedTime))"){edit(id){$0.end=preview.displayedTime;if ($0.start ?? 0)>preview.displayedTime{$0.start=project.trimStart}}}
                        Text("\(LoopFormat.time(track.start ?? project.trimStart)) to \(LoopFormat.time(track.end ?? project.trimEnd))")
                        Slider(value:Binding(get:{track.start ?? project.trimStart},set:{v in edit(id){$0.start=min(v,($0.end ?? project.trimEnd)-0.01)}}),in:project.trimStart...max(project.trimStart+0.01,project.trimEnd-0.01)){Text("Start")}
                        Slider(value:Binding(get:{track.end ?? project.trimEnd},set:{v in edit(id){$0.end=max(v,($0.start ?? project.trimStart)+0.01)}}),in:project.trimStart...project.trimEnd){Text("End")}
                    }
                    Section("Ease in and out"){
                        Stepper("Fade in: \(track.fadeIn,specifier:"%.1f") s",value:Binding(get:{track.fadeIn},set:{v in edit(id){$0.fadeIn=v}}),in:0...3,step:0.1)
                        Stepper("Fade out: \(track.fadeOut,specifier:"%.1f") s",value:Binding(get:{track.fadeOut},set:{v in edit(id){$0.fadeOut=v}}),in:0...3,step:0.1)
                    }
                    Section("Change strength over time"){
                        Button("Remember current strength here"){edit(id){$0.remember($0.amount,at:preview.displayedTime)}}
                        Text("\(track.keys.count) strength points. Loop blends smoothly between them.").font(.caption)
                        Button("Clear strength points"){edit(id){$0.keys=[]}}
                    }
                }
            }.navigationTitle("Effect timing").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){timingID=nil}}}
        }
    }
}
