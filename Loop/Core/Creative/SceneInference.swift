import Foundation
import CoreML
import CoreImage
import CoreVideo
@preconcurrency import Vision

/// Models are bundled and loaded on demand. This type never performs network work.
enum SceneModels {
    static let lock=NSRecursiveLock()
    private static var loaded:[String:MLModel]=[:]
    static let context=CIContext(options:[.cacheIntermediates:false])
    static let rgb=CGColorSpace(name:CGColorSpace.sRGB)!
    static func purge(){lock.lock();loaded.removeAll();context.clearCaches();lock.unlock()}
    static func model(_ name:String)throws->MLModel {
        lock.lock();defer{lock.unlock()}
        if let value=loaded[name]{return value}
        guard let url=Bundle.main.url(forResource:name,withExtension:"mlmodelc") else {
            throw LoopError.encoding("The bundled \(name) model is missing. Install the complete Loop update.")
        }
        let configuration=MLModelConfiguration()
        // SAM's variable prompt shapes follow the upstream CPU/GPU execution path.
        configuration.computeUnits = name.hasPrefix("SAM2") ? .cpuAndGPU : .all
        let value=try MLModel(contentsOf:url,configuration:configuration)
        loaded[name]=value
        return value
    }
    static func buffer(_ image:CIImage,width:Int,height:Int)throws->CVPixelBuffer {
        var result:CVPixelBuffer?
        guard CVPixelBufferCreate(nil,width,height,kCVPixelFormatType_32BGRA,[kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&result)==kCVReturnSuccess,let result else {
            throw LoopError.encoding("Not enough memory for scene analysis.")
        }
        let e=image.extent
        let scaled=image.transformed(by:CGAffineTransform(translationX:-e.minX,y:-e.minY))
            .transformed(by:CGAffineTransform(scaleX:CGFloat(width)/e.width,y:CGFloat(height)/e.height))
        context.render(scaled,to:result,bounds:CGRect(x:0,y:0,width:width,height:height),colorSpace:rgb)
        return result
    }
    static func raster(_ image:CIImage,edge:CGFloat=512)throws->CGImage {
        let factor=min(1,edge/max(image.extent.width,image.extent.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        guard let cg=context.createCGImage(small,from:small.extent,format:.RGBA8,colorSpace:rgb) else{throw LoopError.encoding("The scene frame could not be read.")}
        return cg
    }
    static func scalar(_ array:MLMultiArray,_ offset:Int)->Float {
        switch array.dataType {
        case .float32:return array.dataPointer.assumingMemoryBound(to:Float.self)[offset]
        case .float16:return Float(array.dataPointer.assumingMemoryBound(to:Float16.self)[offset])
        case .double:return Float(array.dataPointer.assumingMemoryBound(to:Double.self)[offset])
        default:return array[offset].floatValue
        }
    }
    /// Tensor planes are top-left; CI image construction is flipped explicitly.
    static func plane(_ array:MLMultiArray,channel:Int=0,normalize:Bool=false,logits:Bool=false)throws->CIImage {
        let shape=array.shape.map(\.intValue),strides=array.strides.map(\.intValue)
        guard shape.count>=2 else{throw LoopError.encoding("The scene model returned an invalid image shape.")}
        let h=shape[shape.count-2],w=shape[shape.count-1]
        guard w>0,h>0,w*h<=4_194_304 else{throw LoopError.encoding("The scene model's image is too large.")}
        let offset=shape.count>=3 ? channel*strides[shape.count-3]:0
        var values=[Float](repeating:0,count:w*h)
        var low=Float.greatestFiniteMagnitude,high = -Float.greatestFiniteMagnitude
        for y in 0..<h {for x in 0..<w {
            let f=scalar(array,offset+y*strides[shape.count-2]+x*strides[shape.count-1])
            let v=f.isFinite ? f:0
            values[y*w+x]=v;low=min(low,v);high=max(high,v)
        }}
        if normalize {
            let sample=values.enumerated().filter{$0.offset%31==0}.map(\.element).sorted()
            if sample.count>20 {low=sample[sample.count/100];high=sample[min(sample.count-1,sample.count*99/100)]}
        }
        var bytes=[UInt8](repeating:0,count:w*h)
        for i in values.indices {
            let v:Float
            if logits {v=1/(1+exp(-max(-30,min(30,values[i]))))}
            else if normalize {v=(values[i]-low)/max(0.00001,high-low)}
            else {v=values[i]}
            bytes[i]=UInt8((max(0,min(1,v))*255).rounded())
        }
        let raw=CIImage(bitmapData:Data(bytes),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil)
        return raw.transformed(by:CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:CGFloat(h)))
    }
    static func fit(_ image:CIImage,to e:CGRect)->CIImage {
        image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
            .transformed(by:CGAffineTransform(scaleX:e.width/image.extent.width,y:e.height/image.extent.height))
            .transformed(by:CGAffineTransform(translationX:e.minX,y:e.minY)).cropped(to:e)
    }
    static func depth(_ image:CIImage)throws->CIImage {
        lock.lock();defer{lock.unlock()}
        let model=try model("DepthAnythingV2SmallF16")
        guard let input=model.modelDescription.inputDescriptionsByName.first(where:{$0.value.type == .image}),let c=input.value.imageConstraint else{throw LoopError.encoding("The depth model has no image input.")}
        let pixel=try buffer(image,width:c.pixelsWide,height:c.pixelsHigh)
        let output=try model.prediction(from:MLDictionaryFeatureProvider(dictionary:[input.key:MLFeatureValue(pixelBuffer:pixel)]))
        for name in output.featureNames {
            if let a=output.featureValue(for:name)?.multiArrayValue {return fit(try plane(a,normalize:true),to:image.extent)}
            if let b=output.featureValue(for:name)?.imageBufferValue {
                // This pinned Core ML model emits normalized inverse depth in a
                // grayscale-half image. Treat it as data, not display color.
                let raw=CIImage(cvPixelBuffer:b,options:[.colorSpace:NSNull()])
                let normalized=raw.applyingFilter("CIColorClamp",parameters:[
                    "inputMinComponents":CIVector(x:0,y:0,z:0,w:0),
                    "inputMaxComponents":CIVector(x:1,y:1,z:1,w:1)])
                return fit(normalized,to:image.extent)
            }
        }
        throw LoopError.encoding("The depth model returned no depth map.")
    }
}

/// Independent implementation of the public SAM2 Core ML image/prompt/mask contract.
/// Image embeddings are shared across all selected subjects in the current frame.
enum PromptSelection {
    struct Prompt {var id:UUID;var points:[SelectionPoint];var box:NormalizedRect?}
    static func masks(_ image:CIImage,prompts:[Prompt])throws->[UUID:CIImage] {
        guard !prompts.isEmpty else{return [:]}
        SceneModels.lock.lock();defer{SceneModels.lock.unlock()}
        let encoder=try SceneModels.model("SAM2TinyImageEncoderFLOAT16")
        let promptModel=try SceneModels.model("SAM2TinyPromptEncoderFLOAT16")
        let decoder=try SceneModels.model("SAM2TinyMaskDecoderFLOAT16")
        guard let imageInput=encoder.modelDescription.inputDescriptionsByName.first(where:{$0.value.type == .image}),let c=imageInput.value.imageConstraint else{throw LoopError.encoding("The selection model has no image input.")}
        let encoded=try encoder.prediction(from:MLDictionaryFeatureProvider(dictionary:[imageInput.key:MLFeatureValue(pixelBuffer:try SceneModels.buffer(image,width:c.pixelsWide,height:c.pixelsHigh))]))
        var result:[UUID:CIImage]=[:]
        for prompt in prompts.prefix(3) {
            var coordinates=prompt.points.map{(CGFloat($0.x),CGFloat($0.y),$0.include ? 1:0)}
            let hint=prompt.box ?? (prompt.points.count==1 ? initialObjectBox(image,point:prompt.points[0]):nil)
            if let b=hint {coordinates += [(b.x,b.y,2),(b.x+b.width,b.y+b.height,3)]}
            if coordinates.isEmpty {continue}
            // The bundled prompt encoder already adds its own no-point token.
            // Prompt encoding appends one token; the bundled decoder permits 15.
            coordinates=Array(coordinates.prefix(14))
            let pointsType=promptModel.modelDescription.inputDescriptionsByName["points"]?.multiArrayConstraint?.dataType ?? .float16
            let labelsType=promptModel.modelDescription.inputDescriptionsByName["labels"]?.multiArrayConstraint?.dataType ?? .float16
            let points=try MLMultiArray(shape:[1,NSNumber(value:coordinates.count),2],dataType:pointsType)
            let labels=try MLMultiArray(shape:[1,NSNumber(value:coordinates.count)],dataType:labelsType)
            for (i,p) in coordinates.enumerated() {
                points[[0,NSNumber(value:i),0]]=NSNumber(value:Double(p.0)*Double(c.pixelsWide))
                points[[0,NSNumber(value:i),1]]=NSNumber(value:Double(p.1)*Double(c.pixelsHigh))
                labels[[0,NSNumber(value:i)]]=NSNumber(value:p.2)
            }
            let encodedPrompt=try promptModel.prediction(from:MLDictionaryFeatureProvider(dictionary:["points":points,"labels":labels]))
            var features:[String:MLFeatureValue]=[:]
            let aliases=["sparse_embedding":"sparse_embeddings","dense_embedding":"dense_embeddings"]
            for name in decoder.modelDescription.inputDescriptionsByName.keys {
                if let f=encoded.featureValue(for:name) ?? encodedPrompt.featureValue(for:name) ?? encodedPrompt.featureValue(for:aliases[name] ?? name){features[name]=f}
            }
            guard features.count==decoder.modelDescription.inputDescriptionsByName.count else {throw LoopError.encoding("The selection model components do not match.")}
            // Prompt outputs may be strided views. Give the decoder a compact
            // token tensor, without adding a second no-point padding token.
            if let a=features["sparse_embedding"]?.multiArrayValue {
                let type=decoder.modelDescription.inputDescriptionsByName["sparse_embedding"]?.multiArrayConstraint?.dataType ?? a.dataType
                let compact=try MLMultiArray(shape:a.shape,dataType:type)
                for i in 0..<a.count {compact[i]=a[i]}
                features["sparse_embedding"]=MLFeatureValue(multiArray:compact)
            }
            let output=try decoder.prediction(from:MLDictionaryFeatureProvider(dictionary:features))
            guard let masks=output.featureValue(for:"low_res_masks")?.multiArrayValue,
                  let scores=output.featureValue(for:"scores")?.multiArrayValue else{throw LoopError.encoding("The selection model returned no mask.")}
            let candidates=(0..<scores.count).map{SceneModels.scalar(scores,$0)}
            let index=candidates.indices.max(by:{candidates[$0]<candidates[$1]}) ?? 0
            guard candidates[index].isFinite,candidates[index]>0.25 else{continue}
            let mask=SceneModels.fit(try SceneModels.plane(masks,channel:index,logits:true),to:image.extent)
            result[prompt.id]=mask
        }
        return result
    }
    private static func initialObjectBox(_ image:CIImage,point:SelectionPoint)->NormalizedRect? {
        guard point.include else{return nil}
        do {
            let cg=try SceneModels.raster(image,edge:768)
            let handler=VNImageRequestHandler(cgImage:cg,orientation:.up,options:[:])
            let request=VNGenerateForegroundInstanceMaskRequest();try handler.perform([request])
            guard let observation=request.results?.first else{return nil}
            let labels=observation.instanceMask
            CVPixelBufferLockBaseAddress(labels,.readOnly)
            let label:Int
            if let base=CVPixelBufferGetBaseAddress(labels)?.assumingMemoryBound(to:UInt8.self) {
                let w=CVPixelBufferGetWidth(labels),h=CVPixelBufferGetHeight(labels),stride=CVPixelBufferGetBytesPerRow(labels)
                let x=min(w-1,max(0,Int(point.x*Double(w)))),y=min(h-1,max(0,Int(point.y*Double(h))))
                label=Int(base[y*stride+x])
            } else {label=0}
            CVPixelBufferUnlockBaseAddress(labels,.readOnly)
            guard label>0 else{return nil}
            let buffer=try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:label),from:handler)
            let b=try bounds(of:CIImage(cvPixelBuffer:buffer))
            return b.width*b.height>0.01 ? b:nil
        } catch {return nil}
    }
    static func bounds(of mask:CIImage)throws->NormalizedRect {
        let w=192,h=192
        let small=SceneModels.fit(mask,to:CGRect(x:0,y:0,width:w,height:h))
        var rgba=[UInt8](repeating:0,count:w*h*4)
        SceneModels.context.render(small,toBitmap:&rgba,rowBytes:w*4,bounds:small.extent,format:.RGBA8,colorSpace:SceneModels.rgb)
        let bytes=stride(from:0,to:rgba.count,by:4).map{rgba[$0]}
        var minX=w,maxX = -1,minY=h,maxY = -1
        for y in 0..<h {for x in 0..<w where bytes[(y*w+x)*4]>128 {minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}}
        guard maxX>minX,maxY>minY else{throw LoopError.invalidSettings("No clear subject was found at that point. Tap its center or add another point.")}
        return NormalizedRect(x:Double(minX)/Double(w),y:Double(h-1-maxY)/Double(h),width:Double(maxX-minX+1)/Double(w),height:Double(maxY-minY+1)/Double(h)).clamped()
    }
}

struct SceneFrame {
    var depth:CIImage?
    var masks:[UUID:CIImage]=[:]
    var parts:[String:CIImage]=[:]
    var portrait:DetailedPortrait?
}
final class SceneRuntime: @unchecked Sendable {
    private let lock=NSRecursiveLock()
    private var lastKey=""
    private var lastScene:SceneSettings?
    private var lastFrame:SceneFrame?
    private var oldDepth:CGImage?
    private var oldSource:CGImage?
    private var oldTime = -Double.infinity
    private var maskSource:CGImage?
    private var oldMasks:[UUID:CGImage]=[:]
    private var maskTime = -Double.infinity
    func reset(){lock.lock();defer{lock.unlock()};lastFrame=nil;oldDepth=nil;oldSource=nil;lastKey="";oldTime = -.infinity;oldMasks=[:];maskSource=nil;maskTime = -.infinity}
    func analyze(_ image:CIImage,settings:SceneSettings,time:Double,portrait:Bool,parts:Bool)throws->SceneFrame {
        lock.lock();defer{lock.unlock()}
        let key="\(time)-\(image.extent)-\(portrait)-\(parts)"
        if key==lastKey,lastScene==settings,let cached=lastFrame{return cached}
        var output=SceneFrame()
        if portrait || parts {
            let result=try PortraitModels.analyze(image,mesh:portrait,parts:parts)
            output.portrait=result;output.parts=result.masks
        }
        if settings.depthEnabled {
            var depth=try SceneModels.depth(image)
            let now=try SceneModels.raster(image,edge:384)
            if settings.flowEnabled,abs(time-oldTime)>0.0001,time>oldTime,time-oldTime<0.18,
               let oldSource,let oldDepth,oldSource.width==now.width,oldSource.height==now.height {
                let aligned=try SceneOpticalFlow.warp(CIImage(cgImage:oldDepth),from:oldSource,to:now,extent:image.extent)
                let oldImage=SceneModels.fit(CIImage(cgImage:oldSource),to:image.extent)
                depth=try RealismKernels.color("loopTemporalMatte",extent:image.extent,arguments:[depth,aligned,image,oldImage,0.45])
            }
            oldDepth=try SceneModels.raster(depth,edge:384);oldSource=now;oldTime=time;output.depth=depth
        }
        let subjects=settings.subjects.filter{$0.covers(time)}
        let prompts=subjects.map { s->PromptSelection.Prompt in
            let box=s.box(at:time)
            let points=s.points.map { p->SelectionPoint in
                SelectionPoint(x:box.x+(p.x-s.rect.x)/s.rect.width*box.width,y:box.y+(p.y-s.rect.y)/s.rect.height*box.height,include:p.include)
            }
            return PromptSelection.Prompt(id:s.id,points:points,box:box)
        }
        if settings.preciseSelection {output.masks=try PromptSelection.masks(image,prompts:prompts)}
        else if !subjects.isEmpty {output.masks=try nativeMasks(image,subjects:subjects,time:time)}
        for subject in subjects {
            if let mask=output.masks[subject.id] {output.masks[subject.id]=try MaskPainter.apply(subject.strokes,to:mask,box:subject.box(at:time))}
        }
        if !output.masks.isEmpty {
            let now=try SceneModels.raster(image,edge:384)
            if settings.flowEnabled,lastScene?.subjects==settings.subjects,time>maskTime,time-maskTime<0.18,
               let old=maskSource,old.width==now.width,old.height==now.height {
                for (id,mask) in output.masks {
                    if let previous=oldMasks[id] {
                        let aligned=try SceneOpticalFlow.warp(CIImage(cgImage:previous),from:old,to:now,extent:image.extent)
                        output.masks[id]=try RealismKernels.color("loopTemporalMatte",extent:image.extent,arguments:[mask,aligned,image,SceneModels.fit(CIImage(cgImage:old),to:image.extent),0.5])
                    }
                }
            }
            oldMasks=try output.masks.mapValues{try SceneModels.raster($0,edge:384)};maskSource=now;maskTime=time
        }
        lastKey=key;lastScene=settings;lastFrame=output
        return output
    }
    private func nativeMasks(_ image:CIImage,subjects:[SceneSubject],time:Double)throws->[UUID:CIImage] {
        let source=try SceneModels.raster(image,edge:768)
        let handler=VNImageRequestHandler(cgImage:source,orientation:.up,options:[:])
        let request=VNGenerateForegroundInstanceMaskRequest();try handler.perform([request])
        guard let observation=request.results?.first else{return [:]}
        var result:[UUID:CIImage]=[:]
        let labels=observation.instanceMask
        CVPixelBufferLockBaseAddress(labels,.readOnly);defer{CVPixelBufferUnlockBaseAddress(labels,.readOnly)}
        guard let base=CVPixelBufferGetBaseAddress(labels)?.assumingMemoryBound(to:UInt8.self) else{return result}
        let w=CVPixelBufferGetWidth(labels),h=CVPixelBufferGetHeight(labels),stride=CVPixelBufferGetBytesPerRow(labels)
        for subject in subjects {
            let b=subject.box(at:time)
            let x=min(w-1,max(0,Int(b.centerX*Double(w)))),y=min(h-1,max(0,Int(b.centerY*Double(h))))
            let label=Int(base[y*stride+x]);guard label>0 else{continue}
            let buffer=try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:label),from:handler)
            result[subject.id]=SceneModels.fit(CIImage(cvPixelBuffer:buffer),to:image.extent)
        }
        return result
    }
}

/// Dense Vision flow is preferred. Some OS installations do not include its
/// neural weights; bounded translation alignment keeps preview/export usable.
enum SceneOpticalFlow {
    private static let lock = NSLock()
    private static var nativeUnavailable = false
    /// Dense flow is preferred; unavailable OS model assets must not break playback.
    static func warp(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)throws->CIImage {
        lock.lock();defer{lock.unlock()}
        if !nativeUnavailable {
            do {
                let request=VNGenerateOpticalFlowRequest(targetedCGImage:old,options:[:])
                request.computationAccuracy = .medium
                request.outputPixelFormat=kCVPixelFormatType_TwoComponent32Float
                try VNImageRequestHandler(cgImage:current,orientation:.up,options:[:]).perform([request])
                if let buffer=request.results?.first?.pixelBuffer {
                    let flow=SceneModels.fit(CIImage(cvPixelBuffer:buffer,options:[.colorSpace:NSNull()]),to:extent)
                    return try RealismKernels.general("loopFlowAlign",extent:extent,arguments:[SceneModels.fit(mask,to:extent).clampedToExtent(),flow,CIVector(x:extent.width/CGFloat(current.width),y:extent.height/CGFloat(current.height))],padding:max(extent.width,extent.height)*0.2)
                }
            } catch {nativeUnavailable=true}
        }
        return translated(mask,from:old,to:current,extent:extent)
    }
    /// Bounded global translation fallback, not dense deformation. Low-match
    /// frames are left unshifted and the compositor's motion gate rejects them.
    static func translation(from old:CGImage,to current:CGImage)->CGPoint {
        let w=96,h=96,radius=10
        let bounds=CGRect(x:0,y:0,width:w,height:h)
        func luminance(_ source:CGImage)->[UInt8] {
            var bytes=[UInt8](repeating:0,count:w*h*4)
            SceneModels.context.render(SceneModels.fit(CIImage(cgImage:source),to:bounds),toBitmap:&bytes,rowBytes:w*4,bounds:bounds,format:.RGBA8,colorSpace:SceneModels.rgb)
            return (0..<w*h).map{i in UInt8((Int(bytes[i*4])*54+Int(bytes[i*4+1])*183+Int(bytes[i*4+2])*19)/256)}
        }
        let a=luminance(old),b=luminance(current),margin=radius+2
        func error(_ dx:Int,_ dy:Int)->Double {
            var sum=0.0,count=0
            for y in stride(from:margin,to:h-margin,by:3) {for x in stride(from:margin,to:w-margin,by:3) {
                let d=Double(Int(b[y*w+x])-Int(a[(y-dy)*w+x-dx]))/255
                sum+=d*d;count+=1
            }}
            return sum/Double(max(1,count))
        }
        let initial=error(0,0)
        guard initial>0.00001 else{return .zero}
        var best=initial,offset=CGPoint.zero
        for dy in -radius...radius {for dx in -radius...radius {
            let score=error(dx,dy)
            if score<best-0.0000001 {best=score;offset=CGPoint(x:dx,y:dy)}
        }}
        guard best<0.03,best<initial*0.94 else{return .zero}
        return CGPoint(x:offset.x/CGFloat(w),y:offset.y/CGFloat(h))
    }
    static func translated(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)->CIImage {
        let delta=translation(from:old,to:current)
        return SceneModels.fit(mask,to:extent).transformed(by:CGAffineTransform(translationX:delta.x*extent.width,y:delta.y*extent.height))
            .composited(over:CIImage(color:.black).cropped(to:extent)).cropped(to:extent)
    }
}
