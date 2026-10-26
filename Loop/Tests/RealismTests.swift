import XCTest
import CoreImage
import Vision
import ImageIO
import UniformTypeIdentifiers
@testable import Loop

final class RealismTests: XCTestCase {
    private let context=CIContext(options:[.cacheIntermediates:false])
    private let extent=CGRect(x:0,y:0,width:128,height:128)
    private func color(_ image:CIImage,x:Int=64,y:Int=64)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:4)
        context.render(image,toBitmap:&bytes,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        return bytes
    }
    func testRetiredMasksAreRemoved() {
        for id in ["cat","fox","skull","clown","robot","galaxyBody","goldStatue","paperBody"] {XCTAssertNil(EffectLibrary.preset(id))}
        for id in ["faceSculpt","waistDefine","ageOlder","skinSilk","ph_venice_sunset","rain"] {XCTAssertNotNil(EffectLibrary.preset(id))}
        XCTAssertEqual(Set(EffectLibrary.presets.map(\.id)).count,EffectLibrary.presets.count)
    }
    func testLegacySettingsDecode() throws {
        let value=try JSONDecoder().decode(EffectSettings.self,from:Data(#"{"layers":[],"bypass":false}"#.utf8))
        XCTAssertNil(value.faceTuning);XCTAssertNil(value.matteTuning)
    }
    func testPresetChangeResetsOnlyMatchingTuning() {
        var value=EffectSettings();value.faceTuning=FaceTuning();value.bodyTuning=BodyTuning()
        value.select("faceSlim",category:.face)
        XCTAssertNil(value.faceTuning);XCTAssertNotNil(value.bodyTuning)
    }
    func testShadersLoad() throws {
        for name in ["loopReshape","loopSkinMask","loopBilateral","loopRetouch","loopTemporalMatte","loopRefineMatte","loopAgingDetail","loopWeather"] {_ = try RealismKernels.kernel(name)}
    }
    func testZeroReshapeIsIdentity() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.5,blue:0.7)).cropped(to:extent)
        let result=try PortraitTransforms.reshape(PortraitSurface(image:image,mask:nil),center:CGPoint(x:64,y:64),radii:CGSize(width:40,height:40))
        XCTAssertEqual(color(image),color(result.image))
    }
    func testShapeChangesPixelsNotPaint() throws {
        let image=CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:128,y:0),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:extent)
        let result=try PortraitTransforms.reshape(PortraitSurface(image:image,mask:image),center:CGPoint(x:64,y:64),radii:CGSize(width:60,height:60),sx:0.35)
        XCTAssertNotEqual(color(image,x:86),color(result.image,x:86))
        XCTAssertEqual(color(result.image,x:86),color(try XCTUnwrap(result.mask),x:86))
        XCTAssertEqual(color(image,x:2),color(result.image,x:2))
    }
    func testBilateralPreservesConstantColor() throws {
        let image=CIImage(color:CIColor(red:0.2,green:0.4,blue:0.6)).cropped(to:extent)
        let result=try RealismKernels.general("loopBilateral",extent:extent,arguments:[image.clampedToExtent(),CIVector(x:1,y:0)])
        let a=color(image),b=color(result)
        for i in 0..<4 {XCTAssertLessThanOrEqual(abs(Int(a[i])-Int(b[i])),2)}
    }
    func testBehindAtmosphereDoesNotPaintForeground() throws {
        let image=CIImage(color:CIColor(red:0.25,green:0.4,blue:0.3)).cropped(to:extent)
        let mask=CIImage(color:.white).cropped(to:extent)
        var tuning=AtmosphereTuning();tuning.placement="behind";tuning.density=1
        for id in RealismAtmosphere.modes {
            let output=try RealismAtmosphere.apply(image,id:id,time:1.4,mask:mask,amount:1,tuning:tuning)
            XCTAssertEqual(color(image),color(output),id)
        }
    }
    func testAtmosphereIsDeterministicAndAnimated() throws {
        let image=CIImage(color:.black).cropped(to:extent)
        var tuning=AtmosphereTuning();tuning.placement="front";tuning.density=1
        let a=try RealismAtmosphere.apply(image,id:"fog",time:2,mask:nil,amount:1,tuning:tuning)
        let b=try RealismAtmosphere.apply(image,id:"fog",time:2,mask:nil,amount:1,tuning:tuning)
        let c=try RealismAtmosphere.apply(image,id:"fog",time:20,mask:nil,amount:1,tuning:tuning)
        XCTAssertEqual(color(a),color(b));XCTAssertNotEqual(color(a),color(c))
    }
    func testMotionGateRejectsOldMatte() throws {
        let black=CIImage(color:.black).cropped(to:extent),white=CIImage(color:.white).cropped(to:extent)
        let result=try RealismKernels.color("loopTemporalMatte",extent:extent,arguments:[black,white,white,black,1.0])
        XCTAssertEqual(color(result)[0],0)
    }
    func testBundledAssets() throws {
        for name in ["LoopAging","LoopMatte"] {XCTAssertNotNil(Bundle.main.url(forResource:name,withExtension:"mlmodelc"),name)}
        for id in EffectLibrary.inCategory(.background).map(\.id).filter({$0.hasPrefix("ph_")}) {
            let background=try RealismBackdrop.make(CIImage(color:.black).cropped(to:extent),id:id,time:0,custom:nil,tuning:BackdropTuning())
            XCTAssertEqual(background.extent,extent)
            XCTAssertGreaterThan(color(background)[3],250)
        }
    }
    func testModelsProduceNativeImages() throws {
        let image=CIImage(color:CIColor(red:0.4,green:0.5,blue:0.6)).cropped(to:CGRect(x:0,y:0,width:512,height:512))
        for name in ["LoopAging","LoopMatte"] {
            let output=try LocalPortraitModels.predict(image,name:name)
            XCTAssertEqual(output.extent.width,512);XCTAssertEqual(output.extent.height,512)
        }
    }
    func testFullVideoImportStillDefault() {
        let metadata=VideoMetadata(name:"Check",duration:21,size:PixelSize(width:1920,height:1080),nominalFrameRate:30,isHDR:false,byteCount:0)
        XCTAssertEqual(LoopProject(name:"Check",sourceFilename:"check.mp4",metadata:metadata).trimEnd,21)
    }
    func testBodyWarpUsesPoseGeometry() throws {
        let image=CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:128,y:0),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:extent)
        let pose=BodyGeometry(joints:["ls":CGPoint(x:0.3,y:0.85),"rs":CGPoint(x:0.7,y:0.85),"lh":CGPoint(x:0.38,y:0.35),"rh":CGPoint(x:0.62,y:0.35)])
        var tuning=BodyTuning();tuning.waist=1
        let result=try PortraitTransforms.body(PortraitSurface(image:image,mask:image),bodies:[pose],tuning:tuning,amount:1)
        XCTAssertNotEqual(color(image,x:78,y:68),color(result.image,x:78,y:68))
        XCTAssertEqual(color(result.image,x:78,y:68),color(try XCTUnwrap(result.mask),x:78,y:68))
    }
    func testPortraitFixtureRendering() throws {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"portrait-fixture",withExtension:"png"))
        let source=try XCTUnwrap(CIImage(contentsOf:url))
        let analysis=try RealismAnalysis.analyze(source,faces:true,person:true,body:false,preview:false,time:0,tuning:MatteTuning(),session:nil)
        XCTAssertFalse(analysis.geometry.isEmpty,"The real portrait must produce usable landmarks.")
        let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LoopRealismChecks")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        func write(_ image:CIImage,_ name:String) throws {
            let cg=try XCTUnwrap(context.createCGImage(image,from:source.extent))
            let path=folder.appendingPathComponent(name+".png")
            let destination=try XCTUnwrap(CGImageDestinationCreateWithURL(path as CFURL,UTType.png.identifier as CFString,1,nil))
            CGImageDestinationAddImage(destination,cg,nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
        try write(source,"original")
        try write(try XCTUnwrap(analysis.personMask),"matte")
        for (id,category) in [("faceSculpt",EffectCategory.face),("skinSilk",.face),("ageOlder",.face),("rain",.atmosphere),("bubbles",.atmosphere),("ph_venice_sunset",.background)] {
            var settings=EffectSettings();settings.select(id,category:category)
            let result=try RealismCompositor.apply(source,settings:settings,time:1.2,preview:false,analysis:analysis,session:nil)
            XCTAssertEqual(result.extent,source.extent)
            try write(result,id)
        }
        var settings=EffectSettings();settings.select("rain",category:.atmosphere)
        settings.select("ph_forest_slope",category:.background)
        try write(try RealismCompositor.apply(source,settings:settings,time:1.2,preview:false,analysis:analysis,session:nil),"layered-rain")
    }

}
