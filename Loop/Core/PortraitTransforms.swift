import Foundation
import CoreImage
import CoreGraphics

struct PortraitSurface {
    var image: CIImage
    var mask: CIImage?
}

enum PortraitTransforms {
    static func point(_ p: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX+p.x*extent.width,y:extent.minY+p.y*extent.height)
    }
    static func reshape(_ surface: PortraitSurface, center: CGPoint, radii: CGSize,
                        axis: CGPoint = CGPoint(x:1,y:0), sx: Double = 0, sy: Double = 0,
                        shift: CGPoint = .zero) throws -> PortraitSurface {
        guard radii.width>1,radii.height>1, abs(sx)+abs(sy)+abs(shift.x)+abs(shift.y)>0.00001 else { return surface }
        guard let kernel = try RealismKernels.kernel("loopReshape") as? CIWarpKernel else { throw LoopError.encoding("The shape shader could not be loaded.") }
        let args: [Any] = [CIVector(cgPoint:center),CIVector(x:radii.width,y:radii.height),CIVector(cgPoint:axis),CIVector(x:sx,y:sy),CIVector(cgPoint:shift)]
        let padding=max(radii.width,radii.height)*0.35+max(abs(shift.x),abs(shift.y))
        func warp(_ image:CIImage) throws -> CIImage {
            guard let result=kernel.apply(extent:image.extent,roiCallback:{_,r in r.insetBy(dx:-padding,dy:-padding)},image:image.clampedToExtent(),arguments:args) else { throw LoopError.encoding("The shape effect could not be rendered.") }
            return result.cropped(to:image.extent)
        }
        return PortraitSurface(image:try warp(surface.image),mask:try surface.mask.map(warp))
    }
    static func face(_ surface:PortraitSurface,id:String,geometry:[FaceGeometry],tuning:FaceTuning,amount:Double) throws -> PortraitSurface {
        var result=surface
        let e=surface.image.extent
        for face in geometry where abs(face.yaw)<0.7 {
            let b=CGRect(x:face.bounds.minX*e.width,y:face.bounds.minY*e.height,width:face.bounds.width*e.width,height:face.bounds.height*e.height)
            guard b.width>=24,b.height>=24 else {continue}
            let le=point(face.leftEye,in:e),re=point(face.rightEye,in:e),mouth=point(face.mouth,in:e),nose=point(face.nose,in:e)
            let d=max(1,hypot(re.x-le.x,re.y-le.y))
            let axis=CGPoint(x:(re.x-le.x)/d,y:(re.y-le.y)/d)
            // Source pixels are displaced at the actual render resolution. No raster stickers.
            result=try reshape(result,center:CGPoint(x:b.midX,y:b.midY),radii:CGSize(width:b.width*0.70,height:b.height*0.76),axis:axis,sx:tuning.width*amount*0.22)
            let jawCenter=CGPoint(x:b.midX,y:b.minY+b.height*0.24)
            result=try reshape(result,center:jawCenter,radii:CGSize(width:b.width*0.62,height:b.height*0.45),axis:axis,sx:tuning.jaw*amount*0.22)
            result=try reshape(result,center:CGPoint(x:b.midX,y:b.minY+b.height*0.09),radii:CGSize(width:b.width*0.35,height:b.height*0.35),axis:axis,shift:CGPoint(x:axis.y*b.height*CGFloat(tuning.chin*amount)*0.055,y:-axis.x*b.height*CGFloat(tuning.chin*amount)*0.055))
            for eye in [le,re] {result=try reshape(result,center:eye,radii:CGSize(width:d*0.42,height:d*0.31),axis:axis,sx:-tuning.eyes*amount*0.22,sy:-tuning.eyes*amount*0.18)}
            result=try reshape(result,center:nose,radii:CGSize(width:b.width*0.24,height:b.height*0.26),axis:axis,sx:tuning.nose*amount*0.26)
            result=try reshape(result,center:mouth,radii:CGSize(width:b.width*0.30,height:b.height*0.20),axis:axis,sx:-tuning.lips*amount*0.12,sy:-tuning.lips*amount*0.26)
            let mask=try skinMask(face,extent:e,excludeFeatures:true)
            if id == "faceBlur" || id == "facePixel" {
                let treatment = id == "faceBlur"
                    ? result.image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:b.width*0.09*max(0.15,amount)]).cropped(to:e)
                    : result.image.applyingFilter("CIPixellate",parameters:[kCIInputScaleKey:max(3,b.width*0.065*amount)])
                result.image=treatment.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result.image,kCIInputMaskImageKey:try skinMask(face,extent:e,excludeFeatures:false)])
            } else if id == "ageOlder" || id == "ageMature" {
                let strength=amount*(id == "ageMature" ? 0.5:0.9)
                result.image=try aged(result.image,face:face,mask:mask,amount:strength)
            } else if abs(tuning.skin)+abs(tuning.detail)+abs(tuning.warmth)>0.001 {
                let area=b.insetBy(dx:-b.width*0.18,dy:-b.height*0.2).intersection(e)
                let input=result.image.clampedToExtent()
                let radius=max(1.5,b.width*0.012)
                let horizontal=try RealismKernels.general("loopBilateral",extent:area,arguments:[input,CIVector(x:radius/4,y:0)],padding:radius+2)
                let smooth=try RealismKernels.general("loopBilateral",extent:area,arguments:[horizontal.clampedToExtent(),CIVector(x:0,y:radius/4)],padding:radius+2)
                let treatment=try RealismKernels.color("loopRetouch",extent:area,arguments:[result.image,smooth,tuning.skin*amount,tuning.detail*amount,tuning.warmth*amount])
                result.image=treatment.composited(over:result.image).applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result.image,kCIInputMaskImageKey:mask])
            }
        }
        return result
    }
    static func skinMask(_ face:FaceGeometry,extent:CGRect,excludeFeatures:Bool) throws -> CIImage {
        let b=face.bounds,le=point(face.leftEye,in:extent),re=point(face.rightEye,in:extent),m=point(face.mouth,in:extent)
        let width=b.width*extent.width,height=b.height*extent.height
        let zero:CGFloat=excludeFeatures ? 1:0.00001
        return try RealismKernels.color("loopSkinMask",extent:extent,arguments:[
            CIVector(x:b.midX*extent.width,y:(b.midY+0.045*b.height)*extent.height,z:width*0.51,w:height*0.66),
            CIVector(x:le.x,y:le.y,z:width*0.18*zero,w:height*0.10*zero),
            CIVector(x:re.x,y:re.y,z:width*0.18*zero,w:height*0.10*zero),
            CIVector(x:m.x,y:m.y,z:width*0.24*zero,w:height*0.10*zero)])
    }
    static func aged(_ image:CIImage,face:FaceGeometry,mask:CIImage,amount:Double) throws -> CIImage {
        let e=image.extent,b=face.bounds
        // The public model is trained on a 512px crop with a face about half its width.
        let side=max(b.width*e.width,b.height*e.height)*1.85
        let crop=CGRect(x:b.midX*e.width-side/2,y:b.midY*e.height-side/2+side*0.035,width:side,height:side)
        let factor=512/side
        let normalized=image.clampedToExtent().cropped(to:crop)
            .transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY))
            .transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        let generated=try LocalPortraitModels.predict(normalized,name:"LoopAging")
            .transformed(by:CGAffineTransform(scaleX:1/factor,y:1/factor))
            .transformed(by:CGAffineTransform(translationX:crop.minX,y:crop.minY))
        let area=crop.intersection(e)
        let originalLow=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.8,side/512)]).cropped(to:area)
        let detail=try RealismKernels.color("loopAgingDetail",extent:area,arguments:[image,originalLow,generated,0.65])
        let mixed=OfflineEffectsRenderer.blend(image,detail.composited(over:image),amount:amount)
        return mixed.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask]).cropped(to:e)
    }
    static func body(_ surface:PortraitSurface,bodies:[BodyGeometry],tuning:BodyTuning,amount:Double) throws -> PortraitSurface {
        var result=surface
        let e=surface.image.extent
        func mid(_ a:CGPoint,_ b:CGPoint)->CGPoint{CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)}
        for body in bodies.prefix(3) {
            guard let lsn=body.joints["ls"],let rsn=body.joints["rs"],let lhn=body.joints["lh"],let rhn=body.joints["rh"] else{continue}
            let ls=point(lsn,in:e),rs=point(rsn,in:e),lh=point(lhn,in:e),rh=point(rhn,in:e)
            let shoulders=mid(ls,rs),hips=mid(lh,rh)
            let length=max(1,hypot(shoulders.x-hips.x,shoulders.y-hips.y))
            let up=CGPoint(x:(shoulders.x-hips.x)/length,y:(shoulders.y-hips.y)/length)
            let across=CGPoint(x:up.y,y:-up.x)
            let breadth=max(hypot(ls.x-rs.x,ls.y-rs.y),hypot(lh.x-rh.x,lh.y-rh.y)*1.2)
            guard breadth>20,length>24 else{continue}
            let waist=CGPoint(x:hips.x+(shoulders.x-hips.x)*0.35,y:hips.y+(shoulders.y-hips.y)*0.35)
            result=try reshape(result,center:waist,radii:CGSize(width:breadth*0.85,height:length*0.55),axis:across,sx:tuning.waist*amount*0.23)
            result=try reshape(result,center:shoulders,radii:CGSize(width:breadth*0.95,height:length*0.35),axis:across,sx:-tuning.shoulders*amount*0.20)
            result=try reshape(result,center:hips,radii:CGSize(width:breadth*0.8,height:length*0.45),axis:across,sx:-tuning.hips*amount*0.22)
            result=try reshape(result,center:mid(hips,shoulders),radii:CGSize(width:breadth*0.85,height:length*0.75),axis:across,sy:-tuning.torso*amount*0.16)
            for side in ["l","r"] {
                if let hip=body.joints[side+"h"],let ankle=body.joints[side+"a"] {
                    let h=point(hip,in:e),a=point(ankle,in:e),len=hypot(h.x-a.x,h.y-a.y)
                    if len>20 {let axis=CGPoint(x:(h.y-a.y)/len,y:-(h.x-a.x)/len)
                        result=try reshape(result,center:mid(h,a),radii:CGSize(width:breadth*0.46,height:len*0.72),axis:axis,sy:-tuning.legs*amount*0.18)
                    }
                }
                if let shoulder=body.joints[side+"s"],let elbow=body.joints[side+"e"] {
                    let s=point(shoulder,in:e),a=point(elbow,in:e),len=hypot(s.x-a.x,s.y-a.y)
                    if len>12 {let axis=CGPoint(x:(s.y-a.y)/len,y:-(s.x-a.x)/len)
                        result=try reshape(result,center:mid(s,a),radii:CGSize(width:breadth*0.25,height:len*0.7),axis:axis,sx:tuning.arms*amount*0.22)
                    }
                }
            }
        }
        return result
    }
}
