import Foundation
import CoreImage
import CoreGraphics
@preconcurrency import AVFoundation

struct LoopSuggestion:Identifiable,Sendable {
    var id=UUID()
    var start:Double
    var end:Double
    var score:Double
}
enum LoopFinder {
    static func signature(_ image:CGImage)throws->[Float] {
        var pixels=[UInt8](repeating:0,count:32*24*4)
        guard let c=CGContext(data:&pixels,width:32,height:24,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw LoopError.encoding("Loop analysis could not allocate its thumbnail.")}
        c.draw(image,in:CGRect(x:0,y:0,width:32,height:24))
        return stride(from:0,to:pixels.count,by:4).map {i in (Float(pixels[i])*0.2126+Float(pixels[i+1])*0.7152+Float(pixels[i+2])*0.0722)/255}
    }
    static func distance(_ a:[Float],_ b:[Float])->Double {
        guard a.count==b.count,!a.isEmpty else{return 1}
        return Double(zip(a,b).reduce(Float(0)){$0+abs($1.0-$1.1)})/Double(a.count)
    }
    static func find(url:URL,project:LoopProject,around:Double,control:ExportControl,progress:@escaping @Sendable(Double)->Void)async throws->[LoopSuggestion] {
        let start=max(project.trimStart,min(around,project.trimEnd-1)),end=min(project.trimEnd,start+12)
        guard end-start>=1 else{throw LoopError.invalidSettings("Select at least one second to find a loop.")}
        let rate=8.0,count=min(97,Int((end-start)*rate)+1)
        let generator=MediaEngine.makeGenerator(url:url,maximumDimension:96);defer{generator.cancelAllCGImageGeneration()}
        var images=[[Float]]()
        for i in 0..<count {
            try await control.checkpoint()
            let time=min(end-1/60000,start+Double(i)/rate)
            let cg=try await generator.image(at:CMTime(seconds:time,preferredTimescale:60000)).image
            images.append(try signature(cg));progress(Double(i+1)/Double(count))
        }
        var choices=[LoopSuggestion]()
        for i in 0..<max(0,count-9) {for j in (i+8)..<min(count-1,i+65) {
            let appearance=distance(images[i],images[j])
            let da=zip(images[i+1],images[i]).map{$0-$1},db=zip(images[j+1],images[j]).map{$0-$1}
            let motion=distance(da,db)
            choices.append(LoopSuggestion(start:start+Double(i)/rate,end:start+Double(j)/rate,score:appearance+motion*0.5))
        }}
        var result=[LoopSuggestion]()
        for candidate in choices.sorted(by:{$0.score<$1.score}) {
            if result.allSatisfy({abs($0.start-candidate.start)>0.5 || abs($0.end-candidate.end)>0.5}){result.append(candidate)}
            if result.count==3{break}
        }
        return result
    }
}

enum CreativeMotion {
    static func seamDuration(_ project:LoopProject)->Double {
        guard project.export.playback == .forward,let s=project.motion?.seamBlend,s.isFinite else{return 0}
        return max(0,min(s,project.duration*0.25))
    }
    static func apply(_ input:CIImage,project:LoopProject,time:Double,preview:Bool)throws->CIImage {
        guard let motion=project.motion else{return input}
        let e=input.extent,edge=Int(max(e.width,e.height))
        var image=input
        let blend=seamDuration(project)
        if blend>0,time>project.trimEnd-blend {
            let otherTime=project.trimStart+time-(project.trimEnd-blend)
            let cg=try CreativeAssets.source(project:project,time:otherTime,edge:edge,highRange:!preview && project.export.hdrOutput==true)
            let incoming=SceneModels.fit(CIImage(cgImage:cg),to:e)
            let t=(time-(project.trimEnd-blend))/blend
            image=OfflineEffectsRenderer.blend(image,incoming,amount:t*t*(3-2*t))
        }
        if motion.mode != "off",let asset=motion.referenceAsset {
            let reference: CIImage
            if !preview, project.export.hdrOutput == true {
                reference=CIImage(cgImage:try CreativeAssets.source(project:project,time:motion.referenceTime,edge:edge,highRange:true))
            } else {reference=try CreativeAssets.image(asset)}
            let still=SceneModels.fit(reference,to:e)
            let targetTime=motion.mode=="freezeSubject" ? motion.referenceTime:time
            let targetImage=motion.mode=="freezeSubject" ? still:image
            let mask=try selectionMask(targetImage,project:project,id:motion.subjectID,time:targetTime)
            if motion.mode=="freezeSubject" {image=still.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask])}
            else {image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:still,kCIInputMaskImageKey:mask])}
        }
        if motion.echoCount>0 {
            var background=image
            for index in (1...min(3,motion.echoCount)).reversed() {
                let t=time-Double(index)*max(0.03,motion.echoSpacing)
                guard t>=project.trimStart else{continue}
                let cg=try CreativeAssets.source(project:project,time:t,edge:edge)
                let echo=SceneModels.fit(CIImage(cgImage:cg),to:e)
                let mask=try selectionMask(echo,project:project,id:motion.subjectID,time:t)
                let faded=mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:motion.echoStrength/Double(index),y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:motion.echoStrength/Double(index),z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:motion.echoStrength/Double(index),w:0)])
                background=echo.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:faded])
            }
            let mask=try selectionMask(image,project:project,id:motion.subjectID,time:time)
            image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:mask])
        }
        return image.cropped(to:e)
    }
    static func selectionMask(_ image:CIImage,project:LoopProject,id:UUID?,time:Double)throws->CIImage {
        if let id,let subject=project.effects?.scene?.subjects.first(where:{$0.id==id}) {
            guard subject.covers(time) else{throw LoopError.invalidSettings("Track the chosen subject across this clip before using it for motion or export.")}
            var scene=SceneSettings();scene.subjects=[subject]
            let analysis=try SceneRuntime().analyze(image,settings:scene,time:time,portrait:false,parts:false)
            return analysis.masks[id] ?? CIImage(color:.black).cropped(to:image.extent)
        }
        return try RealismAnalysis.analyze(image,faces:false,person:true,body:false,preview:false,time:time,tuning:MatteTuning(),session:nil).personMask ?? CIImage(color:.black).cropped(to:image.extent)
    }
}
