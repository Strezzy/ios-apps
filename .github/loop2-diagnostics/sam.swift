import Foundation
import CoreML
import CoreImage
import CoreVideo
import ImageIO

let root=URL(fileURLWithPath:CommandLine.arguments[1])
let source=CIImage(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))!
let context=CIContext(options:[.cacheIntermediates:false])
let srgb=CGColorSpace(name:CGColorSpace.sRGB)!
let configuration=MLModelConfiguration();configuration.computeUnits = .cpuAndGPU
let models=try ["SAM2TinyImageEncoderFLOAT16","SAM2TinyPromptEncoderFLOAT16","SAM2TinyMaskDecoderFLOAT16"].map{try MLModel(contentsOf:MLModel.compileModel(at:root.appendingPathComponent($0+".mlpackage")),configuration:configuration)}
let encoder=models[0],prompt=models[1],decoder=models[2]
func raw(_ a:MLMultiArray,_ offset:Int)->Float {
 switch a.dataType {
 case .float16:return Float(a.dataPointer.assumingMemoryBound(to:Float16.self)[offset])
 case .float32:return a.dataPointer.assumingMemoryBound(to:Float.self)[offset]
 case .double:return Float(a.dataPointer.assumingMemoryBound(to:Double.self)[offset])
 default:return a[offset].floatValue
 }
}
var buffer:CVPixelBuffer?
CVPixelBufferCreate(nil,1024,1024,kCVPixelFormatType_32BGRA,[kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary,&buffer)
context.render(source.transformed(by:CGAffineTransform(scaleX:1024/source.extent.width,y:1024/source.extent.height)),to:buffer!,bounds:CGRect(x:0,y:0,width:1024,height:1024),colorSpace:srgb)
let encoded=try encoder.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":MLFeatureValue(pixelBuffer:buffer!)]))
let prompts:[[(Double,Double,Int)]]=[[(0.5,0.65,1)],[(0.5,0.65,1),(0.02,0.02,2),(0.74,0.98,3)],[(0.42,0.32,1),(0.25,0.55,1),(0.02,0.02,2),(0.74,0.98,3)]]
for pointSet in prompts {
 let points=try MLMultiArray(shape:[1,NSNumber(value:pointSet.count),2],dataType:.float16)
 let labels=try MLMultiArray(shape:[1,NSNumber(value:pointSet.count)],dataType:.float16)
 for(i,p) in pointSet.enumerated(){points[[0,NSNumber(value:i),0]]=NSNumber(value:p.0*1024);points[[0,NSNumber(value:i),1]]=NSNumber(value:p.1*1024);labels[[0,NSNumber(value:i)]]=NSNumber(value:p.2)}
 let encodedPrompt=try prompt.prediction(from:MLDictionaryFeatureProvider(dictionary:["points":points,"labels":labels]))
 var original:[String:MLFeatureValue]=[:]
 for key in decoder.modelDescription.inputDescriptionsByName.keys {
  let alias=["sparse_embedding":"sparse_embeddings","dense_embedding":"dense_embeddings"][key] ?? key
  original[key]=encoded.featureValue(for:key) ?? encodedPrompt.featureValue(for:alias)
 }
 let sparse=original["sparse_embedding"]!.multiArrayValue!
 print("PROMPT",pointSet.count,"shape",sparse.shape,"strides",sparse.strides,"type",sparse.dataType)
 for mode in ["direct","flatCopy","indexedCopy"] {
  var features=original
  if mode != "direct" {
   let compact=try MLMultiArray(shape:sparse.shape,dataType:sparse.dataType)
   if mode=="flatCopy" {for i in 0..<sparse.count {compact[i]=sparse[i]}}
   else {for n in 0..<sparse.shape[1].intValue {for j in 0..<sparse.shape[2].intValue {let at:[NSNumber]=[0,NSNumber(value:n),NSNumber(value:j)];compact[at]=sparse[at]}}}
   features["sparse_embedding"]=MLFeatureValue(multiArray:compact)
  }
  let output=try decoder.prediction(from:MLDictionaryFeatureProvider(dictionary:features))
  let a=output.featureValue(for:"low_res_masks")!.multiArrayValue!
  let scores=output.featureValue(for:"scores")!.multiArrayValue!
  print("OUTPUT",mode,"shape",a.shape,"strides",a.strides,"type",a.dataType,"scores",(0..<scores.count).map{scores[$0].floatValue})
  let strides=a.strides.map(\.intValue),h=a.shape[2].intValue,w=a.shape[3].intValue
  for c in 0..<3 {
   var bytes=[UInt8](repeating:0,count:w*h),rawBytes=bytes
   var low=Float.infinity,high = -Float.infinity,rawLow=Float.infinity,rawHigh = -Float.infinity,diff=Float(0)
   for y in 0..<h {for x in 0..<w {
    let value=a[[0,NSNumber(value:c),NSNumber(value:y),NSNumber(value:x)]].floatValue
    let pointerValue=raw(a,c*strides[1]+y*strides[2]+x*strides[3])
    low=min(low,value);high=max(high,value);rawLow=min(rawLow,pointerValue);rawHigh=max(rawHigh,pointerValue);diff=max(diff,abs(value-pointerValue))
    bytes[y*w+x]=UInt8((255/(1+exp(-max(-30,min(30,value))))).rounded())
    rawBytes[y*w+x]=UInt8((255/(1+exp(-max(-30,min(30,pointerValue))))).rounded())
   }}
   print("MASK",c,"range",low,high,"rawRange",rawLow,rawHigh,"maxDelta",diff)
   for (kind,data) in [("indexed",bytes),("raw",rawBytes)] {
    let mask=CIImage(bitmapData:Data(data),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil)
    let cg=context.createCGImage(mask,from:mask.extent)!
    let url=URL(fileURLWithPath:"sam-\(pointSet.count)-\(mode)-\(c)-\(kind).png")
    let dst=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dst,cg,nil);CGImageDestinationFinalize(dst)
   }
  }
 }
}
