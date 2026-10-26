import Foundation
import CoreImage
import CoreVideo
@preconcurrency import Vision

/// Selects real Vision foreground instances. It never substitutes a rectangle,
/// the entire frame or all people for the user's explicitly selected subject.
enum NativeSubjectSelection {
    static func masks(_ image:CIImage,prompts:[PromptSelection.Prompt])throws->[UUID:CIImage] {
        guard !prompts.isEmpty else{return [:]}
        let source=try SceneModels.raster(image,edge:1024)
        let handler=VNImageRequestHandler(cgImage:source,orientation:.up,options:[:])
        let request=VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation=request.results?.first,!observation.allInstances.isEmpty else {
            throw LoopError.invalidSettings("No clear foreground object was found. Try a clearer frame or tap nearer its center.")
        }
        let buffer=observation.instanceMask
        guard CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_OneComponent8 else {
            throw LoopError.encoding("This system returned an unsupported subject-label image.")
        }
        let width=CVPixelBufferGetWidth(buffer),height=CVPixelBufferGetHeight(buffer)
        guard width>0,height>0 else{throw LoopError.encoding("The subject-label image is empty.")}
        var labels=[UInt8](repeating:0,count:width*height)
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        if let base=CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to:UInt8.self) {
            let stride=CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {for x in 0..<width {labels[y*width+x]=base[y*stride+x]}}
        }
        CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
        func instance(at point:SelectionPoint)->Int {
            guard point.x.isFinite,point.y.isFinite,(0...1).contains(point.x),(0...1).contains(point.y) else{return 0}
            let x=min(width-1,Int(point.x*Double(width))),y=min(height-1,Int(point.y*Double(height)))
            return Int(labels[y*width+x])
        }
        var output:[UUID:CIImage]=[:]
        for prompt in prompts.prefix(3) {
            try Task.checkCancellation()
            let included=Set(prompt.points.filter(\.include).map(instance).filter{$0>0 && observation.allInstances.contains($0)})
            let excluded=Set(prompt.points.filter{!$0.include}.map(instance).filter{$0>0})
            guard !included.isEmpty else {
                throw LoopError.invalidSettings("That tap did not land on a clear foreground object. Tap its center, then use Keep or Remove to refine the edge.")
            }
            guard included.isDisjoint(with:excluded) else {
                throw LoopError.invalidSettings("Native selection groups those areas together. Undo the last selection tap and use the Keep or Remove brush for fine repairs.")
            }
            let selected=IndexSet(included.subtracting(excluded))
            let maskBuffer=try observation.generateScaledMaskForImage(forInstances:selected,from:handler)
            let mask=SceneModels.fit(CIImage(cvPixelBuffer:maskBuffer),to:image.extent)
            let bounds=try PromptSelection.bounds(of:mask)
            if let box=prompt.box {
                let overlap=bounds.cgRect.intersection(box.cgRect)
                let area=overlap.isNull ? 0:overlap.width*overlap.height
                let smallest=max(0.0001,min(bounds.width*bounds.height,box.width*box.height))
                guard area/smallest>0.15 else {
                    throw LoopError.invalidSettings("The selection no longer matches the tracked subject. Repair the selection on this frame before exporting.")
                }
            }
            output[prompt.id]=mask
        }
        return output
    }
}
