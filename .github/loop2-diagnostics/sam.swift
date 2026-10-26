import Foundation
import CoreML
import CoreImage
import CoreVideo
import ImageIO

let root=URL(fileURLWithPath:CommandLine.arguments[1])
let sourceURL=URL(fileURLWithPath:CommandLine.arguments[2])
let source=CIImage(contentsOf:sourceURL)!
let context=CIContext(options:[.cacheIntermediates:false])
let srgb=CGColorSpace(name:CGColorSpace.sRGB)!
let names=["SAM2TinyImageEncoderFLOAT16","SAM2TinyPromptEncoderFLOAT16","SAM2TinyMaskDecoderFLOAT16"]
var compiled:[URL]=[]
for name in names {compiled.append(try MLModel.compileModel(at:root.appendingPathComponent(name+".mlpackage")))}
func stats(_ a:MLMultiArray)->String {
    let values=(0..<a.count).map{a[$0].floatValue}
    return "shape=\(a.shape) strides=\(a.strides) range=\(values.min() ?? 0)...\(values.max() ?? 0) mean=\(values.reduce(0,+)/Float(values.count))"
}
for (label,units) in [("cpuGPU",MLComputeUnits.cpuAndGPU),("cpu",.cpuOnly),("all",.all)] {
    let config=MLModelConfiguration();config.computeUnits=units
    let models=try compiled.map{try MLModel(contentsOf:$0,configuration:config)}
    let encoder=models[0],prompt=models[1],decoder=models[2]
    var buffer:CVPixelBuffer?
    CVPixelBufferCreate(nil,1024,1024,kCVPixelFormatType_32BGRA,[kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&buffer)
    let image=source.transformed(by:CGAffineTransform(scaleX:1024/source.extent.width,y:1024/source.extent.height))
    context.render(image,to:buffer!,bounds:CGRect(x:0,y:0,width:1024,height:1024),colorSpace:srgb)
    let encoded=try encoder.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":MLFeatureValue(pixelBuffer:buffer!)]))
    print("MODE",label)
    for name in encoded.featureNames.sorted() {if let a=encoded.featureValue(for:name)?.multiArrayValue {print(name,stats(a))}}
    for pointSet in [[(512.0,512.0,1)],[(512.0,512.0,1),(0.0,0.0,-1)],[(512.0,512.0,1),(128.0,128.0,2),(900.0,1000.0,3)]] {
        let points=try MLMultiArray(shape:[1,NSNumber(value:pointSet.count),2],dataType:prompt.modelDescription.inputDescriptionsByName["points"]!.multiArrayConstraint!.dataType)
        let labels=try MLMultiArray(shape:[1,NSNumber(value:pointSet.count)],dataType:prompt.modelDescription.inputDescriptionsByName["labels"]!.multiArrayConstraint!.dataType)
        for(i,p) in pointSet.enumerated(){points[[0,NSNumber(value:i),0]]=NSNumber(value:p.0);points[[0,NSNumber(value:i),1]]=NSNumber(value:p.1);labels[[0,NSNumber(value:i)]]=NSNumber(value:p.2)}
        let encodedPrompt=try prompt.prediction(from:MLDictionaryFeatureProvider(dictionary:["points":points,"labels":labels]))
        var features:[String:MLFeatureValue]=[:]
        for key in decoder.modelDescription.inputDescriptionsByName.keys {
            let alias=["sparse_embedding":"sparse_embeddings","dense_embedding":"dense_embeddings"][key] ?? key
            features[key]=encoded.featureValue(for:key) ?? encodedPrompt.featureValue(for:alias)
        }
        let output=try decoder.prediction(from:MLDictionaryFeatureProvider(dictionary:features))
        let masks=output.featureValue(for:"low_res_masks")!.multiArrayValue,scores=output.featureValue(for:"scores")!.multiArrayValue
        print("POINTS",pointSet.count,"SCORES",stats(scores!))
        for i in 0..<scores!.count {
            let a=masks!;let h=a.shape[2].intValue,w=a.shape[3].intValue
            var positive=0;var lo=Float.infinity,hi = -Float.infinity
            var bytes=[UInt8](repeating:0,count:w*h)
            for y in 0..<h {for x in 0..<w {
                let v=a[[0,NSNumber(value:i),NSNumber(value:y),NSNumber(value:x)]].floatValue
                lo=min(lo,v);hi=max(hi,v);if v>0 {positive+=1}
                bytes[y*w+x]=UInt8((255/(1+exp(-max(-30,min(30,v))))).rounded())
            }}
            print("CANDIDATE",i,"SCORE",scores![i],"LOGITS",lo,hi,"POSITIVE",positive)
            let mask=CIImage(bitmapData:Data(bytes),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil)
            if let cg=context.createCGImage(mask,from:mask.extent){
                let url=URL(fileURLWithPath:"sam-\(label)-\(pointSet.count)-\(i).png")
                let dest=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
                CGImageDestinationAddImage(dest,cg,nil);CGImageDestinationFinalize(dest)
            }
        }
    }
}
