import Foundation
import CoreImage
import CoreGraphics
@preconcurrency import UIKit
@preconcurrency import MediaPipeTasksVision

struct DetailedFace {
    var points:[CGPoint]
    var depth:[Float]
    var expressions:[String:Float]
    var bounds:CGRect
    func point(_ index:Int)->CGPoint {points.indices.contains(index) ? points[index]:CGPoint(x:bounds.midX,y:bounds.midY)}
}
struct DetailedPortrait {
    var faces:[DetailedFace]=[]
    var masks:[String:CIImage]=[:]
}

enum PortraitModels {
    private static let lock=NSLock()
    private static var faceModel:FaceLandmarker?
    private static var partsModel:ImageSegmenter?
    static func purge(){lock.lock();faceModel=nil;partsModel=nil;lock.unlock()}
    static func analyze(_ image:CIImage,mesh:Bool,parts:Bool)throws->DetailedPortrait {
        lock.lock();defer{lock.unlock()}
        var output=DetailedPortrait()
        guard mesh || parts else{return output}
        let cg=try SceneModels.raster(image,edge:768)
        let input=try MPImage(uiImage:UIImage(cgImage:cg))
        if mesh {
            if faceModel==nil {
                guard let path=Bundle.main.path(forResource:"face_landmarker",ofType:"task") else{throw LoopError.encoding("The offline face mesh is missing from this installation.")}
                let options=FaceLandmarkerOptions();options.baseOptions.modelAssetPath=path;options.runningMode = .image
                options.numFaces=4;options.minFaceDetectionConfidence=0.6;options.minFacePresenceConfidence=0.6
                options.outputFaceBlendshapes=true
                faceModel=try FaceLandmarker(options:options)
            }
            guard let faceModel else{throw LoopError.encoding("The face mesh could not start.")}
            let result=try faceModel.detect(image:input)
            for (index,landmarks) in result.faceLandmarks.enumerated() {
                guard landmarks.count>=468 else{continue}
                let points=landmarks.map{CGPoint(x:Double($0.x),y:1-Double($0.y))}
                let xs=points.map(\.x),ys=points.map(\.y)
                let box=CGRect(x:xs.min() ?? 0,y:ys.min() ?? 0,width:(xs.max() ?? 1)-(xs.min() ?? 0),height:(ys.max() ?? 1)-(ys.min() ?? 0))
                var expressions:[String:Float]=[:]
                if result.faceBlendshapes.indices.contains(index) {
                    for category in result.faceBlendshapes[index].categories {if let name=category.categoryName{expressions[name]=category.score}}
                }
                output.faces.append(DetailedFace(points:points,depth:landmarks.map(\.z),expressions:expressions,bounds:box))
            }
        }
        if parts {
            if partsModel==nil {
                guard let path=Bundle.main.path(forResource:"selfie_multiclass_256x256",ofType:"tflite") else{throw LoopError.encoding("The offline hair and skin model is missing.")}
                let options=ImageSegmenterOptions();options.baseOptions.modelAssetPath=path;options.runningMode = .image
                options.shouldOutputConfidenceMasks=true;options.shouldOutputCategoryMask=false
                partsModel=try ImageSegmenter(options:options)
            }
            guard let partsModel else{throw LoopError.encoding("The portrait selection model could not start.")}
            let result=try partsModel.segment(image:input)
            for (index,name) in [(1,"hair"),(2,"skin"),(3,"face"),(4,"clothes")] {
                guard let masks=result.confidenceMasks,masks.indices.contains(index) else{continue}
                let mask=masks[index],w=mask.width,h=mask.height
                let pointer=mask.float32Data
                var bytes=[UInt8](repeating:0,count:w*h)
                for i in bytes.indices {bytes[i]=UInt8((min(1,max(0,pointer[i]))*255).rounded())}
                let raw=CIImage(bitmapData:Data(bytes),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil)
                    .transformed(by:CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:CGFloat(h)))
                output.masks[name]=try RealismAnalysis.refined(SceneModels.fit(raw,to:image.extent),image:image,tuning:MatteTuning())
            }
        }
        return output
    }
}

enum MeshPortrait {
    static let cosmetics:Set<String>=["hairCopper","hairRose","hairSilver","hairMidnight","lipRose","lipBerry","cheekWarm","eyeBlue","eyeHazel","smileGlow"]
    static let oval=[10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109]
    static let lips=[61,40,37,0,267,270,291,321,314,17,84,91]
    static let innerLips=[78,82,13,312,308,317,14,87]
    static func geometry(_ old:[FaceGeometry],detail:DetailedPortrait?)->[FaceGeometry] {
        guard let detail else{return old}
        return old.map { face in
            var face=face
            guard let dense=detail.faces.max(by:{intersection($0.bounds,face.bounds)<intersection($1.bounds,face.bounds)}),intersection(dense.bounds,face.bounds)>0.25 else{return face}
            face.leftEye=dense.point(468);face.rightEye=dense.point(473)
            if dense.points.count<478 {face.leftEye=dense.point(159);face.rightEye=dense.point(386)}
            if face.leftEye.x>face.rightEye.x {let saved=face.leftEye;face.leftEye=face.rightEye;face.rightEye=saved}
            face.nose=dense.point(1);face.mouth=dense.point(13);face.contour=oval.map{dense.point($0)}
            return face
        }
    }
    private static func intersection(_ a:CGRect,_ b:CGRect)->CGFloat {
        let i=a.intersection(b);return i.isNull ? 0:i.width*i.height/max(0.00001,b.width*b.height)
    }
    static func polygon(_ points:[CGPoint],extent:CGRect,holes:[[CGPoint]]=[])->CIImage {
        let scale=min(1,2048/max(extent.width,extent.height)),w=max(1,Int(extent.width*scale)),h=max(1,Int(extent.height*scale))
        guard let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else{return CIImage(color:.black).cropped(to:extent)}
        context.setFillColor(gray:0,alpha:1);context.fill(CGRect(x:0,y:0,width:w,height:h))
        func draw(_ ring:[CGPoint],_ white:CGFloat){
            guard let first=ring.first else{return}
            context.beginPath();context.move(to:CGPoint(x:first.x*CGFloat(w),y:first.y*CGFloat(h)))
            for p in ring.dropFirst(){context.addLine(to:CGPoint(x:p.x*CGFloat(w),y:p.y*CGFloat(h)))}
            context.closePath();context.setFillColor(gray:white,alpha:1);context.fillPath()
        }
        draw(points,1);for hole in holes{draw(hole,0)}
        guard let cg=context.makeImage() else{return CIImage(color:.black).cropped(to:extent)}
        return SceneModels.fit(CIImage(cgImage:cg,options:[.colorSpace:NSNull()]),to:extent)
    }
    static func apply(_ image:CIImage,id:String,detail:DetailedPortrait?,amount:Double)throws->CIImage {
        guard let detail else{return image}
        let e=image.extent
        var mask=CIImage(color:.black).cropped(to:e)
        var color=CIColor(red:0.8,green:0.25,blue:0.15)
        var strength=amount
        if id.hasPrefix("hair") {
            guard let hair=detail.masks["hair"] else{return image};mask=hair
            switch id {case "hairRose":color=CIColor(red:0.7,green:0.18,blue:0.35);case "hairSilver":color=CIColor(red:0.65,green:0.68,blue:0.75);case "hairMidnight":color=CIColor(red:0.07,green:0.1,blue:0.22);default:color=CIColor(red:0.64,green:0.24,blue:0.08)}
        } else {
            for face in detail.faces {
                let local:CIImage
                if id.hasPrefix("lip") {local=polygon(lips.map{face.point($0)},extent:e,holes:[innerLips.map{face.point($0)}]);color=id=="lipBerry" ? CIColor(red:0.45,green:0.04,blue:0.15):CIColor(red:0.75,green:0.27,blue:0.34)}
                else if id.hasPrefix("eye") {
                    guard face.points.count>=478 else{continue}
                    let left=polygon([469,470,471,472].map{face.point($0)},extent:e)
                    let right=polygon([474,475,476,477].map{face.point($0)},extent:e)
                    local=left.applyingFilter("CIMaximumCompositing",parameters:[kCIInputBackgroundImageKey:right])
                    color=id=="eyeBlue" ? CIColor(red:0.12,green:0.38,blue:0.65):CIColor(red:0.42,green:0.36,blue:0.12)
                } else {
                    local=polygon(oval.map{face.point($0)},extent:e,holes:[lips.map{face.point($0)}])
                    color=CIColor(red:0.8,green:0.35,blue:0.27)
                    strength=amount*0.16
                    if id=="smileGlow" {strength *= Double(max(face.expressions["mouthSmileLeft"] ?? 0,face.expressions["mouthSmileRight"] ?? 0))}
                }
                mask=local.applyingFilter("CIMaximumCompositing",parameters:[kCIInputBackgroundImageKey:mask])
            }
        }
        let modified=try RealismKernels.color("loopCosmetic",extent:e,arguments:[image,CIVector(x:color.red,y:color.green,z:color.blue),min(1,max(0,strength))])
        return modified.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask]).cropped(to:e)
    }
}

enum MaskPainter {
    static func apply(_ strokes:[MaskStroke],to mask:CIImage,box:NormalizedRect)throws->CIImage {
        guard !strokes.isEmpty else{return mask}
        let e=mask.extent,factor=min(1,1024/max(e.width,e.height)),w=max(1,Int(e.width*factor)),h=max(1,Int(e.height*factor))
        guard let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0),let cg=SceneModels.context.createCGImage(mask,from:e,format:.L8,colorSpace:CGColorSpaceCreateDeviceGray()) else{throw LoopError.encoding("The mask repair could not be drawn.")}
        context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));context.setLineCap(.round);context.setLineJoin(.round)
        for stroke in strokes.suffix(100) {
            guard let first=stroke.points.first else{continue}
            func p(_ a:SelectionPoint)->CGPoint {CGPoint(x:(box.x+a.x*box.width)*Double(w),y:(1-box.y-a.y*box.height)*Double(h))}
            let width=max(1,stroke.width*box.width*Double(w));context.setLineWidth(width)
            context.setStrokeColor(gray:stroke.include ? 1:0,alpha:1);context.setFillColor(gray:stroke.include ? 1:0,alpha:1)
            if stroke.points.count==1 {let a=p(first);context.fillEllipse(in:CGRect(x:a.x-width/2,y:a.y-width/2,width:width,height:width))}
            else {context.beginPath();context.move(to:p(first));for point in stroke.points.dropFirst().prefix(2000){context.addLine(to:p(point))};context.strokePath()}
        }
        guard let result=context.makeImage() else{throw LoopError.encoding("The mask repair could not be saved.")}
        return SceneModels.fit(CIImage(cgImage:result,options:[.colorSpace:NSNull()]),to:e)
    }
}
