import SwiftUI

struct MotionToolsView:View {
    @EnvironmentObject private var store:LoopStore
    @Binding var project:LoopProject
    @ObservedObject var preview:EditorPreview
    @State private var busy=false
    @State private var progress:Double=0
    @State private var suggestions:[LoopSuggestion]=[]
    @State private var error:String?
    @State private var control=ExportControl()
    private var value:MotionSettings{project.motion ?? MotionSettings()}
    private func field<T>(_ path:WritableKeyPath<MotionSettings,T>)->Binding<T>{Binding(get:{value[keyPath:path]},set:{v in var s=value;s[keyPath:path]=v;project.motion=s})}
    var body:some View {
        LoopCard {
            DisclosureGroup("Motion & seamless loops") {
                VStack(alignment:.leading,spacing:14){
                    Text("Make a smoother loop, keep one thing moving, or leave a motion trail. Start with a steady clip for the cleanest result.").font(.caption).foregroundStyle(.secondary)
                    Button("Find a good loop",systemImage:"repeat"){findLoop()}.buttonStyle(.glass).disabled(busy)
                    Text("Checks up to 12 seconds from the playhead. You choose the result; nothing is trimmed automatically.").font(.caption2).foregroundStyle(.secondary)
                    ForEach(Array(suggestions.enumerated()),id:\.element.id){index,suggestion in
                        Button("Try loop \(index+1) · \(LoopFormat.time(suggestion.end-suggestion.start))"){
                            preview.stop();project.trimStart=suggestion.start;project.trimEnd=suggestion.end
                            preview.seek(to:suggestion.start,project:project,url:store.sourceURL(project))
                        }.buttonStyle(.glass)
                    }
                    Toggle("Blend the loop seam",isOn:Binding(get:{value.seamBlend>0},set:{on in field(\.seamBlend).wrappedValue=on ? min(0.3,project.duration*0.15):0}))
                    if value.seamBlend>0 {
                        Slider(value:field(\.seamBlend),in:0.02...max(0.021,min(1,project.duration*0.25)))
                        Text("Overlaps \(value.seamBlend,specifier:"%.2f") seconds at the join. Forward loops only; output is slightly shorter and silent.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Picker("What moves?",selection:field(\.mode)){
                        Text("Normal video").tag("off")
                        Text("Only the subject moves").tag("moveSubject")
                        Text("Freeze the subject").tag("freezeSubject")
                    }.pickerStyle(.menu)
                    if value.mode != "off" {
                        Button(value.referenceAsset==nil ? "Use this frame as the still":"Replace still with this frame",systemImage:"camera"){capture()}.buttonStyle(.glass).disabled(busy)
                        Text(value.referenceAsset==nil ? "Choose a still frame before this effect can run.":"Still frame: \(LoopFormat.time(value.referenceTime))").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Motion subject",selection:field(\.subjectID)){
                        Text("All visible people").tag(nil as UUID?)
                        ForEach(project.effects?.scene?.subjects ?? []){subject in Text(subject.name).tag(Optional(subject.id))}
                    }.pickerStyle(.menu)
                    Text("To isolate an object, choose and track it under Looks first.").font(.caption2).foregroundStyle(.secondary)
                    Stepper("Motion echoes: \(value.echoCount)",value:field(\.echoCount),in:0...3)
                    if value.echoCount>0 {
                        Text("Echoes use real earlier frames. Extra frames take more processing.").font(.caption).foregroundStyle(.secondary)
                        Slider(value:field(\.echoStrength),in:0.05...0.6)
                    }
                    if busy {ProgressView(value:progress);Button("Cancel"){control.cancel()}.font(.caption)}
                    if let error{Text(error).font(.caption).foregroundStyle(.orange)}
                }.padding(.top,12)
            }.font(.subheadline.weight(.semibold))
        }
    }
    private func findLoop(){
        busy=true;progress=0;error=nil;control=ExportControl();let snapshot=project,url=store.sourceURL(project),time=preview.displayedTime,c=control
        Task {
            await preview.suspendForAnalysis()
            defer{busy=false;preview.resumeAfterAnalysis(project:project,url:url)}
            do{suggestions=try await LoopFinder.find(url:url,project:snapshot,around:time,control:c){p in Task{@MainActor in progress=p}}}
            catch{self.error=error.localizedDescription}
        }
    }
    private func capture(){
        busy=true;error=nil;let snapshot=project,url=store.sourceURL(project),time=preview.displayedTime
        Task {
            await preview.suspendForAnalysis();defer{busy=false;preview.resumeAfterAnalysis(project:project,url:url)}
            do {
                let image=try await MediaEngine.thumbnail(url:url,time:time,maximumDimension:4096)
                let path=try await Task.detached{try CreativeAssets.save(image,projectID:snapshot.id)}.value
                var settings=value;settings.referenceAsset=path;settings.referenceTime=time;project.motion=settings
            }catch{self.error=error.localizedDescription}
        }
    }
}
