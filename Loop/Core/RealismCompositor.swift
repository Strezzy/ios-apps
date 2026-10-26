import Foundation
import CoreImage
import CoreGraphics

enum RealismCompositor {
    static func apply(_ input:CIImage,settings:EffectSettings,time:Double,preview:Bool,
                      analysis supplied:EffectsAnalysis? = nil,session:RealismSession? = nil) throws -> CIImage {
        let layers=settings.activeLayers
        guard !layers.isEmpty else{return input}
        let matte=settings.matteTuning ?? MatteTuning()
        let face=layers.first{EffectLibrary.preset($0.preset)?.category == .face}
        let body=layers.first{EffectLibrary.preset($0.preset)?.category == .body}
        let background=layers.first{EffectLibrary.preset($0.preset)?.category == .background}
        let weather=layers.first{EffectLibrary.preset($0.preset)?.category == .atmosphere}
        let analysis=try supplied ?? RealismAnalysis.analyze(input,faces:face != nil,person:background != nil || body != nil || weather != nil,
            body:body != nil,preview:preview,time:time,tuning:matte,session:session)
        var surface=PortraitSurface(image:input,mask:analysis.personMask)
        if let body {
            surface=try PortraitTransforms.body(surface,bodies:analysis.bodies,
                tuning:settings.bodyTuning ?? BodyTuning.recipe(body.preset),amount:clamp(body.amount))
        }
        if let face {
            surface=try PortraitTransforms.face(surface,id:face.preset,geometry:analysis.geometry,
                tuning:settings.faceTuning ?? FaceTuning.recipe(face.preset),amount:clamp(face.amount))
        }
        if let mask=surface.mask {surface.mask=try RealismAnalysis.refined(mask,image:surface.image,tuning:matte)}
        if preview,matte.showMask,let mask=surface.mask{return mask}
        var image=surface.image
        if let background,let mask=surface.mask {
            let back=try RealismBackdrop.make(image,id:background.preset,time:time,custom:settings.backgroundImage,
                tuning:settings.backdropTuning ?? BackdropTuning())
            let composite=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:back,kCIInputMaskImageKey:mask])
            image=OfflineEffectsRenderer.blend(image,composite,amount:clamp(background.amount))
        }
        if let weather {
            image=try RealismAtmosphere.apply(image,id:weather.preset,time:time,mask:surface.mask,
                amount:clamp(weather.amount),tuning:settings.atmosphereTuning ?? AtmosphereTuning())
        }
        // Grade the composite together so subject, photographed background and weather share a palette.
        for category in [EffectCategory.looks,.lens] {
            if let layer=layers.first(where:{EffectLibrary.preset($0.preset)?.category == category}) {
                let modified = category == .looks ? OfflineEffectsRenderer.look(image,id:layer.preset)
                    : OfflineEffectsRenderer.lens(image,id:layer.preset,time:time)
                image=OfflineEffectsRenderer.blend(image,modified,amount:clamp(layer.amount))
            }
        }
        return image.cropped(to:input.extent)
    }
    private static func clamp(_ x:Double)->Double{x.isFinite ? min(1,max(0,x)):0}
}

enum RealismAtmosphere {
    static let modes=["snow","rain","embers","sparkles","dust","bubbles","confetti","fog","lightLeak","fireflies"]
    static func apply(_ image:CIImage,id:String,time:Double,mask:CIImage?,amount:Double,tuning:AtmosphereTuning) throws -> CIImage {
        guard let mode=modes.firstIndex(of:id) else{return image}
        let e=image.extent
        func overlay(_ depth:Double)->CIImage? {
            try? RealismKernels.general("loopWeather",extent:e,arguments:[image.clampedToExtent(),CIVector(x:e.width,y:e.height),time,Double(mode),depth,
                max(0.05,min(1,tuning.density)),max(0.1,min(3,tuning.speed)),max(-1,min(1,tuning.wind)),max(0.1,min(1,tuning.size))],padding:max(e.width,e.height)*0.03)
        }
        guard let far=overlay(0),let middle=overlay(1),let near=overlay(2) else{throw LoopError.encoding("Atmosphere rendering could not start.")}
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
