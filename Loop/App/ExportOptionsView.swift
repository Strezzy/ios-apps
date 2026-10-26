import SwiftUI

struct ExportOptionsView:View {
    @Binding var project:LoopProject
    var body:some View {
        VStack(spacing:16){
            LoopCard {
                EditorSectionTitle(title:"Ready to save",subtitle:"Pick a format. The defaults are ready to use.")
                Picker("Save as",selection:$project.export.format){ForEach(AnimationFormat.allCases){format in Text(format.title).tag(format)}}
                    .pickerStyle(.menu).accessibilityIdentifier("exportFormat")
                Text(project.export.format.detailDescription).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Smaller file"){project.export.maximumDimension=720;project.export.frameRate=min(24,project.metadata.nominalFrameRate)}.buttonStyle(.glass)
                    Button("Source quality"){project.export.maximumDimension=0;project.export.frameRate=min(project.export.format.maximumFrameRate,project.metadata.nominalFrameRate)}.buttonStyle(.glass)
                }
                if project.export.format.isVideo {
                    Toggle("Keep original audio",isOn:Binding(get:{project.export.includeAudio != false},set:{project.export.includeAudio=$0}))
                        .disabled(project.export.playback != .forward || CreativeMotion.seamDuration(project)>0)
                    if project.export.playback != .forward || CreativeMotion.seamDuration(project)>0 {Text("Reverse, ping-pong and seam-blended loops are saved without audio.").font(.caption).foregroundStyle(.secondary)}
                }
                if project.export.format == .hevc {
                    Toggle("Keep HDR highlights · 10-bit HLG",isOn:Binding(get:{project.export.hdrOutput==true},set:{project.export.hdrOutput=$0})).disabled(!project.metadata.isHDR)
                    Text(project.metadata.isHDR ? "Saves a color-managed HLG video, not Dolby Vision. The editor preview is SDR; HDR playback needs a compatible screen.":"This source is standard color. HDR cannot restore highlights that were never captured.").font(.caption).foregroundStyle(.secondary)
                }
                if project.export.format == .apng {
                    Toggle("Remove background",isOn:Binding(get:{project.export.transparentBackground==true},set:{project.export.transparentBackground=$0}))
                }
                if project.export.format == .hevcAlpha || project.export.transparentBackground==true {
                    Text("Keeps the chosen subject, or all people when no subject is selected. Review the cutout before sharing. Save transparent video to Files for use in compatible editors.").font(.caption).foregroundStyle(.secondary)
                }
                outputSummary
            }
            LoopCard {
                DisclosureGroup("Size, smoothness & advanced options"){
                    VStack(alignment:.leading,spacing:16){
                        Text("Frame rate controls smoothness. Resolution controls picture size, not the detail originally captured.").font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal,showsIndicators:false){HStack{
                            ForEach([12.0,15,24,30,50,60],id:\.self){rate in Button("\(Int(rate)) FPS"){project.export.frameRate=rate}.buttonStyle(.glass).accessibilityIdentifier("fps-\(Int(rate))")}
                            Button("Source"){project.export.frameRate=min(project.export.format.maximumFrameRate,project.metadata.nominalFrameRate)}.buttonStyle(.glass)
                        }.padding(2)}
                        Stepper("\(LoopFormat.rate(project.export.frameRate)) frames per second",value:$project.export.frameRate,in:1...project.export.format.maximumFrameRate)
                        Picker("Longest edge",selection:$project.export.maximumDimension){
                            Text("Original crop size").tag(0)
                            ForEach([480,720,1080,1440,2160,3840,4096],id:\.self){n in Text("\(n) pixels").tag(n)}
                            if ![0,480,720,1080,1440,2160,3840,4096].contains(project.export.maximumDimension){Text("Custom · \(project.export.maximumDimension)").tag(project.export.maximumDimension)}
                        }.pickerStyle(.menu).accessibilityIdentifier("exportResolution")
                        Toggle("Allow enlargement",isOn:$project.export.allowUpscaling)
                        if project.export.frameRate*project.export.speed>project.metadata.nominalFrameRate+0.1{Text("This rate repeats source frames. It does not invent extra motion.").font(.caption).foregroundStyle(.secondary)}
                        if project.export.format == .gif {
                            Picker("Colors",selection:$project.export.paletteSize){Text("64").tag(64);Text("128").tag(128);Text("256").tag(256)}.pickerStyle(.segmented)
                            Toggle("Smooth color gradients",isOn:$project.export.dither)
                            Toggle("Consistent colors & smaller changes",isOn:Binding(get:{project.export.stableGIFPalette==true},set:{project.export.stableGIFPalette=$0}))
                            Text("Samples the clip for a shared palette and saves only changed regions. Helps color stability and can reduce file size; adds an analysis pass.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !project.export.format.isVideo {
                            Toggle("Repeat forever",isOn:Binding(get:{project.export.loopCount==0},set:{project.export.loopCount=$0 ? 0:1}))
                            if project.export.loopCount>0{Stepper("Play \(project.export.loopCount) times",value:$project.export.loopCount,in:1...100)}
                        }
                    }.padding(.top,12)
                }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("exportAdvanced")
            }
        }.onChange(of:project.export.format){_,format in
            project.export.frameRate=min(format.maximumFrameRate,project.export.frameRate)
            if format != .hevc{project.export.hdrOutput=false}
            if format != .apng{project.export.transparentBackground=false}
        }
    }
    @ViewBuilder private var outputSummary:some View {
        if let plan=try? ExportPlan(project:project){
            Divider();Text("\(plan.size.label) · \(LoopFormat.time(plan.duration))").font(.headline).monospacedDigit()
            Text("\(plan.frames.count) frames. Preview quality adapts for editing; export uses the chosen size. Large clips and neural effects take more processing.").font(.caption).foregroundStyle(.secondary)
        }else{Text(validationMessage).font(.caption).foregroundStyle(.orange)}
    }
    private var validationMessage:String{do{_ = try ExportPlan(project:project);return ""}catch{return error.localizedDescription}}
}
