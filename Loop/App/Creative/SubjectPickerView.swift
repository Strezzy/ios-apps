import SwiftUI
import CoreImage
import ImageIO

struct SubjectPickerView:View {
    @EnvironmentObject private var store:LoopStore
    @Environment(\.dismiss) private var dismiss
    @Binding var project:LoopProject
    @ObservedObject var preview:EditorPreview
    var editingID:UUID?
    @State private var draft=SceneSubject()
    @State private var source:CGImage?
    @State private var mask:CIImage?
    @State private var overlay:CGImage?
    @State private var mode="select"
    @State private var include=true
    @State private var brush=0.08
    @State private var gesturePoints:[SelectionPoint]=[]
    @State private var busy=false
    @State private var progress:Double?
    @State private var error:String?
    @State private var control=ExportControl()
    @State private var token=UUID()
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text(mode=="select" ? "Tap the person or object you want to change." : "Paint small corrections. Repairs follow the selected subject.")
                        .font(.headline)
                    GeometryReader { geometry in
                        let size=fit(in:geometry.size)
                        ZStack {
                            Color.black
                            if let source {
                                Image(decorative:source,scale:1).resizable().frame(width:size.width,height:size.height)
                                if let overlay{Image(decorative:overlay,scale:1).resizable().frame(width:size.width,height:size.height)}
                                if mode=="select" {ForEach(Array(draft.points.enumerated()),id:\.offset){_,p in
                                    Circle().fill(p.include ? Color.green:Color.red).frame(width:12,height:12)
                                        .position(x:(geometry.size.width-size.width)/2+p.x*size.width,y:(geometry.size.height-size.height)/2+p.y*size.height)
                                }}
                            }
                            if busy{ProgressView().tint(.white)}
                        }.clipShape(.rect(cornerRadius:20)).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance:0).onChanged{v in
                                guard !busy,mode != "select",let p=normalized(v.location,container:geometry.size,fitted:size) else{return}
                                if gesturePoints.count<1500{gesturePoints.append(p)}
                            }.onEnded{v in
                                guard !busy,let point=normalized(v.location,container:geometry.size,fitted:size) else{return}
                                if mode=="select" {draft.points.append(SelectionPoint(x:point.x,y:point.y,include:include));draft.points=Array(draft.points.suffix(24));segment()}
                                else {paint()}
                            })
                    }.frame(height:360).accessibilityElement(children:.ignore).accessibilityLabel("Subject selection canvas").accessibilityHint("Use Choose to select a subject, or Keep and Remove to repair its edge.").accessibilityIdentifier("subjectPickerCanvas")
                    Picker("Selection tool",selection:$mode) {Text("Choose").tag("select");Text("Keep").tag("keep");Text("Remove").tag("remove")}.pickerStyle(.segmented)
                    if mode=="select" {
                        Toggle("Add to selection",isOn:$include)
                        Text(include ? "Add more taps to include missing areas." : "Tap background areas that should be left out.").font(.caption).foregroundStyle(.secondary)
                    } else {Slider(value:$brush,in:0.02...0.3){Text("Brush size")};Text("Brush size").font(.caption).foregroundStyle(.secondary)}
                    TextField("Name this subject",text:$draft.name).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Start over",systemImage:"arrow.counterclockwise"){draft.points=[];draft.strokes=[];draft.path=[];mask=nil;overlay=nil}.buttonStyle(.glass)
                        if !draft.strokes.isEmpty {Button("Undo repair"){draft.strokes.removeLast();segment()}.buttonStyle(.glass)}
                    }.disabled(busy)
                    if let progress {ProgressView(value:progress);Text("Following this subject through the clip…").font(.caption)}
                    if let error{Text(error).font(.callout).foregroundStyle(.orange)}
                    Button(action:track) {
                        Label(busy ? "Analyzing…":"Track & use subject",systemImage:"person.crop.rectangle.badge.checkmark").frame(maxWidth:.infinity).padding(.vertical,9)
                    }.buttonStyle(.glassProminent).disabled(busy || mask==nil)
                    if busy {Button("Cancel analysis"){control.cancel()}.frame(maxWidth:.infinity)}
                    Text("Up to three independent subjects. Tracking can lose fully hidden or very similar objects; uncertain results are not silently assigned to another person.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("Choose subject").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.topBarLeading){Button("Cancel"){control.cancel();dismiss()}.disabled(busy)}}
                .interactiveDismissDisabled(busy)
                .task {
                    preview.stop();source=preview.sourceFrame
                    if let subject=project.effects?.scene?.subjects.first(where:{$0.id==editingID}) {
                        draft=subject
                        let box=subject.box(at:preview.displayedTime)
                        draft.points=subject.points.map{SelectionPoint(x:box.x+($0.x-subject.rect.x)/subject.rect.width*box.width,y:box.y+($0.y-subject.rect.y)/subject.rect.height*box.height,include:$0.include)}
                        draft.rect=box
                    } else {draft.name="Subject \((project.effects?.scene?.subjects.count ?? 0)+1)"}
                    draft.anchorTime=preview.displayedTime
                    if !draft.points.isEmpty{segment()}
                }
        }
    }
    private func fit(in size:CGSize)->CGSize {
        guard let source else{return size};let scale=min(size.width/CGFloat(source.width),size.height/CGFloat(source.height));return CGSize(width:CGFloat(source.width)*scale,height:CGFloat(source.height)*scale)
    }
    private func normalized(_ p:CGPoint,container:CGSize,fitted:CGSize)->SelectionPoint? {
        let x=(p.x-(container.width-fitted.width)/2)/fitted.width,y=(p.y-(container.height-fitted.height)/2)/fitted.height
        guard (0...1).contains(x),(0...1).contains(y) else{return nil}
        return SelectionPoint(x:x,y:y)
    }
    private func segment(){
        guard let source,!draft.points.isEmpty else{return}
        busy=true;error=nil;let id=UUID();token=id;let selection=draft
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated){()->(CIImage,NormalizedRect,CGImage) in
                    let input=CIImage(cgImage:source)
                    guard let raw=try PromptSelection.masks(input,prompts:[.init(id:selection.id,points:selection.points,box:nil)])[selection.id] else{throw LoopError.invalidSettings("No confident subject was found. Tap a clearer area.")}
                    let bounds=try PromptSelection.bounds(of:raw)
                    let repaired=try MaskPainter.apply(selection.strokes,to:raw,box:bounds)
                    let tint=CIImage(color:CIColor(red:0.1,green:0.9,blue:0.65,alpha:0.45)).cropped(to:input.extent)
                    let image=tint.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(color:.clear).cropped(to:input.extent),kCIInputMaskImageKey:repaired])
                    return (repaired,bounds,try SceneModels.raster(image,edge:960))
                }.value
                guard token==id else{return};mask=result.0;draft.rect=result.1;overlay=result.2;draft.path=[]
            }catch{self.error=error.localizedDescription}
            if token==id{busy=false}
        }
    }
    private func paint(){
        guard !gesturePoints.isEmpty else{return}
        let b=draft.rect
        let local=gesturePoints.map{SelectionPoint(x:($0.x-b.x)/b.width,y:($0.y-b.y)/b.height)}
        draft.strokes.append(MaskStroke(points:local,width:brush,include:mode=="keep"));gesturePoints=[];segment()
    }
    private func track(){
        guard mask != nil else{return};busy=true;progress=0;error=nil;control=ExportControl()
        let snapshot=project,subject=draft,url=store.sourceURL(project),controller=control
        Task {
            await preview.suspendForAnalysis()
            do {
                var item=OverlayItem(kind:.cover,startTime:snapshot.trimStart,endTime:snapshot.trimEnd);item.rect=subject.rect
                let path=try await TrackingEngine.track(sourceURL:url,project:snapshot,overlay:item,anchorTime:subject.anchorTime,control:controller){p in Task{@MainActor in progress=p}}
                try await controller.checkpoint()
                var final=subject;final.path=path;final.needsReview=false
                var effects=project.effects ?? EffectSettings(),scene=effects.scene ?? SceneSettings()
                scene.subjects.removeAll{$0.id==final.id}
                guard scene.subjects.count<3 else{throw LoopError.invalidSettings("Remove an existing subject before adding another.")}
                scene.subjects.append(final);scene.selectedID=final.id;effects.scene=scene;project.effects=effects
                preview.resumeAfterAnalysis(project:project,url:url);busy=false;dismiss()
            }catch{self.error=error.localizedDescription;busy=false;progress=nil;preview.resumeAfterAnalysis(project:project,url:url)}
        }
    }
}
