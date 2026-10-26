import Foundation
import CoreGraphics
@preconcurrency import Vision
@preconcurrency import AVFoundation

enum SceneCameraAnalyzer {
    static func analyze(url:URL,project:LoopProject,control:ExportControl,progress:@escaping @Sendable(Double)->Void)async throws->[CameraKey] {
        let count=Int(ceil(project.duration*8))+1
        guard count<=2000 else{throw LoopError.invalidSettings("Analyze camera movement on a clip shorter than four minutes.")}
        let generator=MediaEngine.makeGenerator(url:url,maximumDimension:256);defer{generator.cancelAllCGImageGeneration()}
        var previous:CGImage?,keys=[CameraKey](),x=0.0,y=0.0
        for index in 0..<count {
            try await control.checkpoint()
            let time=min(project.trimEnd-1/60000,project.trimStart+Double(index)/8)
            let image=try await generator.image(at:CMTime(seconds:time,preferredTimescale:60000)).image
            if let old=previous {
                try autoreleasepool {
                    let request=VNTranslationalImageRegistrationRequest(targetedCGImage:old,options:[:])
                    try VNImageRequestHandler(cgImage:image,orientation:.up,options:[:]).perform([request])
                    if let alignment=request.results?.first as? VNImageTranslationAlignmentObservation {
                        let dx = -Double(alignment.alignmentTransform.tx)/Double(image.width),dy = -Double(alignment.alignmentTransform.ty)/Double(image.height)
                        if dx.isFinite,dy.isFinite,abs(dx)<0.2,abs(dy)<0.2{x+=dx;y+=dy}else{x=0;y=0}
                    }
                }
            }
            keys.append(CameraKey(time:time,x:x,y:y));previous=image;progress(Double(index+1)/Double(count));await Task.yield()
        }
        return keys
    }
}
