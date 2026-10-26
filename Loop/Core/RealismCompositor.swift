import Foundation
import CoreImage
import CoreGraphics

enum RealismCompositor {
    static func apply(_ input:CIImage,settings:EffectSettings,time:Double,preview:Bool,
                      analysis supplied:EffectsAnalysis? = nil,session:RealismSession? = nil,
                      transparent:Bool=false) throws -> CIImage {
        guard !settings.bypass || transparent else{return input}
        let tracks=settings.bypass ? []:settings.visibleTracks.filter{$0.strength(at:time)>0}
        let scene=settings.scene ?? SceneSettings()
        let matte=settings.matteTuning ?? MatteTuning()
        let faceTracks=tracks.filter{EffectLibrary.preset($0.preset)?.category == .face}
        let bodyTracks=tracks.filter{EffectLibrary.preset($0.preset)?.category == .body}
        let needsPerson=transparent || !bodyTracks.isEmpty || tracks.contains{let c=EffectLibrary.preset($0.preset)?.category;return c == .background || c == .atmosphere || $0.target != "all"}
        if tracks.isEmpty,!scene.depthEnabled,settings.lut==nil,!transparent{return input}
        let analysis=try supplied ?? RealismAnalysis.analyze(input,faces:!faceTracks.isEmpty,person:needsPerson,body:!bodyTracks.isEmpty,preview:preview,time:time,tuning:matte,session:session)
        let needsParts=tracks.contains{MeshPortrait.cosmetics.contains($0.preset) || ["hair","skin","clothes"].contains($0.target)}
        let runtime=session?.creative ?? SceneRuntime()
        let information=try runtime.analyze(input,settings:scene,time:time,portrait:!faceTracks.isEmpty,parts:needsParts)
        let geometry=MeshPortrait.geometry(analysis.geometry,detail:information.portrait)
        var surface=PortraitSurface(image:input,mask:analysis.personMask)
        func targetMask(_ track:EffectTrack)->CIImage? {
            if let id=track.subjectID{return information.masks[id] ?? CIImage(color:.black).cropped(to:input.extent)}
            if let part=information.parts[track.target]{return part}
            if track.target=="subject"{return surface.mask}
            if track.target=="background"{return surface.mask?.applyingFilter("CIColorInvert")}
            return nil
        }
        func region(_ track:EffectTrack)->NormalizedRect? {scene.subjects.first{$0.id==track.subjectID}?.box(at:time)}
        func selected(_ point:CGPoint,_ box:NormalizedRect)->Bool {box.cgRect.contains(CGPoint(x:point.x,y:1-point.y))}
        for track in faceTracks {
            let before=surface.image,amount=track.strength(at:time)
            let box=region(track)
            let faces=geometry.filter{box==nil || selected(CGPoint(x:$0.bounds.midX,y:$0.bounds.midY),box!)}
            if MeshPortrait.cosmetics.contains(track.preset) {
                surface.image=try MeshPortrait.apply(surface.image,id:track.preset,detail:information.portrait,amount:amount)
            } else {surface=try PortraitTransforms.face(surface,id:track.preset,geometry:faces,tuning:settings.faceTuning ?? FaceTuning.recipe(track.preset),amount:amount)}
            if let mask=targetMask(track){surface.image=surface.image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:before,kCIInputMaskImageKey:mask])}
        }
        for track in bodyTracks {
            let before=surface,box=region(track)
            let bodies=analysis.bodies.filter{body in guard let box,let hip=body.joints["lh"] else{return box==nil};return selected(hip,box)}
            surface=try PortraitTransforms.body(surface,bodies:bodies,tuning:settings.bodyTuning ?? BodyTuning.recipe(track.preset),amount:track.strength(at:time))
            if scene.protectBackground,let oldMask=before.mask,let newMask=surface.mask {
                let background=try RealismKernels.general("loopBackgroundFill",extent:input.extent,arguments:[before.image.clampedToExtent(),oldMask.clampedToExtent(),min(input.extent.width,input.extent.height)*0.15],padding:max(input.extent.width,input.extent.height)*0.15)
                surface.image=surface.image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:background,kCIInputMaskImageKey:newMask])
            }
        }
        if let mask=surface.mask{surface.mask=try RealismAnalysis.refined(mask,image:surface.image,tuning:matte)}
        if preview,matte.showMask,let mask=surface.mask{return mask}
        var image=surface.image
        for track in tracks {
            guard let preset=EffectLibrary.preset(track.preset),preset.category != .face,preset.category != .body else{continue}
            let amount=track.strength(at:time),before=image
            var modified=image
            switch preset.category {
            case .background:
                if let mask=surface.mask {
                    let back=try RealismBackdrop.make(image,id:track.preset,time:time,custom:settings.backgroundImage,tuning:settings.backdropTuning ?? BackdropTuning())
                    let subject=match(image,to:back,strength:scene.matchLighting)
                    modified=subject.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:back,kCIInputMaskImageKey:mask])
                }
            case .atmosphere:
                modified=try RealismAtmosphere.apply(image,id:track.preset,time:time,mask:surface.mask,amount:1,tuning:settings.atmosphereTuning ?? AtmosphereTuning(),depth:information.depth,camera:CameraKey.offset(scene.cameraKeys ?? [],at:time))
            case .looks:modified=OfflineEffectsRenderer.look(image,id:track.preset)
            case .lens:modified=OfflineEffectsRenderer.lens(image,id:track.preset,time:time)
            default:break
            }
            image=OfflineEffectsRenderer.blend(before,modified,amount:amount)
            if let mask=targetMask(track){image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:before,kCIInputMaskImageKey:mask])}
        }
        if let depth=information.depth {
            image=try RealismKernels.general("loopDepthLook",extent:input.extent,arguments:[image.clampedToExtent(),depth.clampedToExtent(),CIVector(x:scene.relight,y:scene.lightWarmth,z:scene.lightDirection,w:scene.depthFog),CIVector(x:scene.focus,y:scene.depthBlur,z:0,w:0),CIVector(x:input.extent.width,y:input.extent.height)],padding:min(input.extent.width,input.extent.height)*0.03)
        }
        if let lut=settings.lut{image=try CubeParser.apply(lut,to:image)}
        if transparent {
            let mask=scene.selectedID.flatMap{information.masks[$0]} ?? surface.mask ?? CIImage(color:.black).cropped(to:input.extent)
            image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(color:.clear).cropped(to:input.extent),kCIInputMaskImageKey:mask])
        }
        return image.cropped(to:input.extent)
    }
    private static func match(_ input:CIImage,to background:CIImage,strength:Double)->CIImage {
        guard strength>0 else{return input}
        func average(_ image:CIImage)->[Float] {
            let average=image.applyingFilter("CIAreaAverage",parameters:[kCIInputExtentKey:CIVector(cgRect:image.extent)])
            var pixels=[Float](repeating:0,count:4)
            SceneModels.context.render(average,toBitmap:&pixels,rowBytes:16,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBAf,colorSpace:SceneModels.rgb)
            return pixels
        }
        let a=average(input),b=average(background)
        let gains=(0..<3).map{i in min(1.25,max(0.8,Double(b[i]+0.04)/Double(a[i]+0.04)))}
        let colored=input.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:gains[0],y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:gains[1],z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:gains[2],w:0)])
        return OfflineEffectsRenderer.blend(input,colored,amount:min(1,strength))
    }
}

enum RealismAtmosphere {
    static let modes=["snow","rain","embers","sparkles","dust","bubbles","confetti","fog","lightLeak","fireflies"]
    static func apply(_ image:CIImage,id:String,time:Double,mask:CIImage?,amount:Double,tuning:AtmosphereTuning,depth:CIImage?=nil,camera:CGPoint = .zero) throws -> CIImage {
        guard let mode=modes.firstIndex(of:id) else{return image}
        let e=image.extent
        func overlay(_ depth:Double)->CIImage? {
            try? RealismKernels.general("loopWeather",extent:e,arguments:[image.clampedToExtent(),CIVector(x:e.width,y:e.height),time,Double(mode),depth,
                max(0.05,min(1,tuning.density)),max(0.1,min(3,tuning.speed)),max(-1,min(1,tuning.wind)),max(0.1,min(1,tuning.size)),CIVector(cgPoint:camera)],padding:max(e.width,e.height)*0.03)
        }
        guard var far=overlay(0),var middle=overlay(1),var near=overlay(2) else{throw LoopError.encoding("Atmosphere rendering could not start.")}
        if let depth,tuning.placement=="layered" {
            far=try RealismKernels.color("loopDepthLayer",extent:e,arguments:[far,depth,0.0,1.0])
            middle=try RealismKernels.color("loopDepthLayer",extent:e,arguments:[middle,depth,1.0,1.0])
            near=try RealismKernels.color("loopDepthLayer",extent:e,arguments:[near,depth,2.0,1.0])
            return OfflineEffectsRenderer.blend(image,near.composited(over:middle.composited(over:far)).composited(over:image),amount:amount).cropped(to:e)
        }
        let behind=middle.composited(over:far).composited(over:image)
        let backgroundOnly:CIImage
        if let mask {backgroundOnly=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:behind,kCIInputMaskImageKey:mask])}
        else{backgroundOnly=behind}
        let result:CIImage
        switch tuning.placement {
        case "behind": result=backgroundOnly
        case "front": result=near.composited(over:middle.composited(over:far)).composited(over:image)
        default:
            let front=near.applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:0.35)])
            result=front.composited(over:backgroundOnly)
        }
        return OfflineEffectsRenderer.blend(image,result,amount:amount).cropped(to:e)
    }
}

enum RealismBackdrop {
    private static let lock=NSLock()
    private static var photographs:[String:CIImage]=[:]
    static func make(_ input:CIImage,id:String,time:Double,custom:Data?,tuning:BackdropTuning) throws -> CIImage {
        let e=input.extent
        var image:CIImage
        if id.hasPrefix("ph_") {
            lock.lock()
            let existing=photographs[id]
            lock.unlock()
            if let existing {image=existing}
            else {
                guard let url=Bundle.main.url(forResource:id,withExtension:"jpg"),let photo=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else{
                    throw LoopError.encoding("The selected photographic background is missing from the app bundle.")
                }
                lock.lock();if photographs.count>=2{photographs.removeAll()};photographs[id]=photo;lock.unlock()
                image=photo
            }
            image=fit(image,to:e,tuning:tuning)
        } else if id == "customBackground",let custom,let photo=CIImage(data:custom,options:[.applyOrientationProperty:true]) {
            image=fit(photo,to:e,tuning:tuning)
        } else {image=OfflineEffectsRenderer.background(input,id:id,time:time,custom:custom)}
        if tuning.blur>0.001 {image=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:min(e.width,e.height)*0.035*min(1,max(0,tuning.blur))]).cropped(to:e)}
        image=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:max(-2,min(2,tuning.exposure))])
        if abs(tuning.warmth)>0.001 {
            image=image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+tuning.warmth*2000,y:0)])
        }
        return image.cropped(to:e)
    }
    private static func fit(_ source:CIImage,to e:CGRect,tuning:BackdropTuning)->CIImage {
        let factor=max(e.width/source.extent.width,e.height/source.extent.height)*max(1,min(2.5,tuning.zoom))
        let scaled=source.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        let x=e.minX-scaled.extent.minX-(scaled.extent.width-e.width)*min(1,max(0,tuning.horizontal))
        let y=e.minY-scaled.extent.minY-(scaled.extent.height-e.height)*min(1,max(0,tuning.vertical))
        return scaled.transformed(by:CGAffineTransform(translationX:x,y:y)).cropped(to:e)
    }
}
