import XCTest
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation
@testable import Loop

final class CreativeTests:XCTestCase {
    let e=CGRect(x:0,y:0,width:128,height:128)
    let context=CIContext(options:[.cacheIntermediates:false])
    func project()->LoopProject{LoopProject(name:"Test",sourceFilename:"source.mov",metadata:VideoMetadata(name:"Test",duration:5,size:PixelSize(width:128,height:128),nominalFrameRate:24,isHDR:false,byteCount:0))}
    func pixel(_ image:CIImage,x:Int=64,y:Int=64)->[UInt8]{var b=[UInt8](repeating:0,count:4);context.render(image,toBitmap:&b,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:SceneModels.rgb);return b}
    func fixture()throws->CIImage{try XCTUnwrap(CIImage(contentsOf:XCTUnwrap(Bundle(for:Self.self).url(forResource:"portrait-fixture",withExtension:"png"))))}
    func testLegacyProjectAndEffectsStillDecode()throws{
        var p=project();p.effects=EffectSettings();p.effects?.select("noir",category:.looks)
        let data=try JSONEncoder().encode(p),decoded=try JSONDecoder().decode(LoopProject.self,from:data)
        XCTAssertNil(decoded.motion);XCTAssertNil(decoded.effects?.scene);XCTAssertEqual(decoded.effects?.layer(.looks)?.preset,"noir")
    }
    func testMixKeepsMultipleEffectsInSameCategory(){var s=EffectSettings();s.add("noir");s.add("goldenHour");s.add("bloom");XCTAssertEqual(s.visibleTracks.count,3);XCTAssertEqual(s.tracks?.map(\.preset),["noir","goldenHour","bloom"])}
    func testMixBoundLimitsWork(){var s=EffectSettings();for _ in 0..<30{s.add("noir")};XCTAssertEqual(s.tracks?.count,12)}
    func testTrackTimingAndFades(){var t=EffectTrack(preset:"noir");t.start=1;t.end=5;t.fadeIn=1;t.fadeOut=1;XCTAssertEqual(t.strength(at:0),0);XCTAssertEqual(t.strength(at:1.5),0.5);XCTAssertEqual(t.strength(at:3),1);XCTAssertEqual(t.strength(at:4.5),0.5);XCTAssertEqual(t.strength(at:6),0)}
    func testStrengthKeysInterpolate(){var t=EffectTrack(preset:"noir");t.remember(0.2,at:1);t.remember(0.8,at:3);XCTAssertEqual(t.strength(at:2),0.5,accuracy:0.001);t.remember(0.6,at:3);XCTAssertEqual(t.keys.count,2);XCTAssertEqual(t.strength(at:3),0.6)}
    func testSubjectDoesNotPretendToTrack(){let s=SceneSubject(anchorTime:2);XCTAssertTrue(s.covers(2));XCTAssertFalse(s.covers(3))}
    func testSelectedSubjectExportRequiresCompleteTrack()throws{var p=project();var s=EffectSettings();let subject=SceneSubject();s.scene=SceneSettings(subjects:[subject]);s.add("noir",target:"subject",subjectID:subject.id);p.effects=s;XCTAssertThrowsError(try ExportPlan(project:p))}
    func testSeamShortensOutputWithoutDuplicateStart()throws{var p=project();p.export.format = .mp4;p.motion=MotionSettings(seamBlend:0.5);let plan=try ExportPlan(project:p);XCTAssertEqual(plan.duration,4.5,accuracy:0.0001);XCTAssertEqual(plan.frames[0].sourceTime,0.5)}
    func testReverseDoesNotUseForwardSeam(){var p=project();p.export.playback = .reverse;p.motion=MotionSettings(seamBlend:0.5);XCTAssertEqual(CreativeMotion.seamDuration(p),0)}
    func testHDRRequiresHEVC()throws{var p=project();p.export.hdrOutput=true;p.export.format = .mp4;XCTAssertThrowsError(try ExportPlan(project:p));p.export.format = .hevc;XCTAssertNoThrow(try ExportPlan(project:p))}
    func testAlphaFormatIsMOV(){XCTAssertEqual(AnimationFormat.hevcAlpha.fileExtension,"mov");XCTAssertTrue(AnimationFormat.hevcAlpha.isVideo)}
    func identityCube()->String{"LUT_3D_SIZE 2\n"+(0..<8).map{i in "\(i%2) \((i/2)%2) \(i/4)"}.joined(separator:"\n")}
    func testCubeParsingAndIdentity()throws{let lut=try CubeParser.parse(Data(identityCube().utf8),name:"Identity");XCTAssertEqual(lut.data.count,128);let image=CIImage(color:CIColor(red:0.4,green:0.5,blue:0.6)).cropped(to:e);let result=try CubeParser.apply(lut,to:image);for(a,b) in zip(pixel(image),pixel(result)){XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),3)}}
    func testCubeRejectsInvalidData(){for data in ["LUT_1D_SIZE 8","LUT_3D_SIZE 100","LUT_3D_SIZE 2\nNaN 1 0",identityCube()+"\n1 1 1"]{XCTAssertThrowsError(try CubeParser.parse(Data(data.utf8),name:"Bad"))}}
    func testSavedLookRemovesClipIdentity(){var s=EffectSettings();let subject=SceneSubject();s.scene=SceneSettings(subjects:[subject],selectedID:subject.id);s.add("noir",target:"subject",subjectID:subject.id);let portable=LookStorage.portable(s);XCTAssertTrue(portable.scene!.subjects.isEmpty);XCTAssertNil(portable.tracks?[0].subjectID)}
    func testReferencePathRejectsTraversal(){XCTAssertThrowsError(try CreativeAssets.image("../../secret.png"))}
    func testCameraPathInterpolation(){let keys=[CameraKey(time:0,x:0,y:0),CameraKey(time:2,x:0.2,y:-0.1)];let p=CameraKey.offset(keys,at:1);XCTAssertEqual(p.x,0.1,accuracy:0.0001);XCTAssertEqual(p.y,-0.05,accuracy:0.0001)}
    func testAllWorldsCreateEditableOfflineMixes(){for world in CinematicWorld.allCases{let s=world.apply(to:EffectSettings());XCTAssertGreaterThan(s.tracks?.count ?? 0,0);XCTAssertTrue(s.scene?.depthEnabled==true);for t in s.tracks ?? []{XCTAssertNotNil(EffectLibrary.preset(t.preset))}}}
    func testNewShadersLoad()throws{for name in ["loopFlowAlign","loopCosmetic","loopDepthLayer","loopDepthLook","loopBackgroundFill","loopLUTDomain"]{_ = try RealismKernels.kernel(name)}}
    func testDepthOccludesFarParticles()throws{let white=CIImage(color:.white).cropped(to:e);let result=try RealismKernels.color("loopDepthLayer",extent:e,arguments:[white,white,0.0,1.0]);XCTAssertEqual(pixel(result)[3],0)}
    func testMaskBrushRemovesSelectedArea()throws{let white=CIImage(color:.white).cropped(to:e);let stroke=MaskStroke(points:[SelectionPoint(x:0.5,y:0.5)],width:0.3,include:false);let result=try MaskPainter.apply([stroke],to:white,box:NormalizedRect(x:0,y:0,width:1,height:1));XCTAssertLessThan(pixel(result)[0],5);XCTAssertGreaterThan(pixel(result,x:5,y:5)[0],250)}
    func testDepthModelProducesUsefulMap()throws{let image=try fixture();let depth=try SceneModels.depth(image);XCTAssertEqual(depth.extent,image.extent);let a=pixel(depth,x:256,y:256),b=pixel(depth,x:480,y:480);XCTAssertNotEqual(a[0],b[0]);try write(depth,"depth")}
    func testDenseFaceAndHairModel()throws{let image=try fixture();let result=try PortraitModels.analyze(image,mesh:true,parts:true);XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.faces.first).points.count,478);XCTAssertNotNil(result.masks["hair"]);try write(try XCTUnwrap(result.masks["hair"]),"hair-mask");try write(MeshPortrait.apply(image,id:"hairCopper",detail:result,amount:0.8),"copper-hair")}
    func testSAMSelectsTappedForeground()throws{let image=try fixture(),id=UUID();let result=try PromptSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.5,y:0.65)],box:nil)]);let mask=try XCTUnwrap(result[id]);XCTAssertGreaterThan(pixel(mask,x:256,y:179)[0],100);let bounds=try PromptSelection.bounds(of:mask);XCTAssertGreaterThan(bounds.width,0.1);try write(mask,"sam-subject")}
    func testFlowWarpProducesFiniteAlignedMask()throws{let image=try fixture();let old=try SceneModels.raster(image,edge:256);let small=CIImage(cgImage:old),shifted=small.transformed(by:CGAffineTransform(translationX:5,y:0)).composited(over:CIImage(color:.black).cropped(to:small.extent)).cropped(to:small.extent);let current=try SceneModels.raster(shifted,edge:256);let mask=CIImage(color:.white).cropped(to:CGRect(x:100,y:80,width:40,height:60)).composited(over:CIImage(color:.black).cropped(to:small.extent));let warped=try SceneOpticalFlow.warp(mask,from:old,to:current,extent:small.extent);XCTAssertEqual(warped.extent,small.extent);XCTAssertGreaterThan(pixel(warped,x:120,y:100)[0],200)}
    func testStablePaletteWritesValidDeltaGIF()throws{let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".gif");defer{try? FileManager.default.removeItem(at:url)};var settings=ExportSettings();settings.stableGIFPalette=true;let base=CIImage(color:CIColor(red:0.2,green:0.4,blue:0.6)).cropped(to:e),changed=CIImage(color:.white).cropped(to:CGRect(x:50,y:50,width:20,height:20)).composited(over:base);let a=try XCTUnwrap(context.createCGImage(base,from:e)),b=try XCTUnwrap(context.createCGImage(changed,from:e));let writer=try GIFEncoder(destination:url,size:PixelSize(width:128,height:128),frameCount:3,settings:settings);try writer.prepareStablePalette([a,b]);try writer.add(a,delay:0.1,gifDelayCentiseconds:10);try writer.add(b,delay:0.1,gifDelayCentiseconds:10);try writer.add(b,delay:0.1,gifDelayCentiseconds:10);try writer.finish();let source=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil));XCTAssertEqual(CGImageSourceGetCount(source),3);XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source,2,nil))}
    func testHDRRenderKeepsFloatingPointOutput()throws{let image=CIImage(color:try XCTUnwrap(CIColor(red:2,green:1.5,blue:1,alpha:1,colorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!))).cropped(to:e);let cg=try XCTUnwrap(context.createCGImage(image,from:e,format:.RGBAh,colorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!));var p=project();p.export.format = .hevc;p.export.hdrOutput=true;let rendered=try FrameRenderer.render(cg,project:p,time:0);XCTAssertGreaterThanOrEqual(rendered.bitsPerComponent,16)}
    func testDepthWorldRendersPortrait()throws{let image=try fixture();let settings=CinematicWorld.winter.apply(to:EffectSettings());let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false);XCTAssertEqual(output.extent,image.extent);try write(output,"winter-world")}
    func write(_ image:CIImage,_ name:String)throws{let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LoopCreativeChecks");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let cg=try XCTUnwrap(context.createCGImage(image,from:image.extent));let dest=try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil));CGImageDestinationAddImage(dest,cg,nil);XCTAssertTrue(CGImageDestinationFinalize(dest))}
    func testMissingSelectedSubjectNeverExportsAllPeople() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.4,blue:0.5)).cropped(to:e)
        var settings=EffectSettings();settings.scene=SceneSettings(selectedID:UUID())
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:EffectsAnalysis(personMask:CIImage(color:.white).cropped(to:e)),transparent:true)
        XCTAssertEqual(pixel(output)[3],0)
    }
    func testMissingSelectedBodyMaskLeavesFrameUnchanged() throws {
        let image=CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:128,y:0),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:e)
        let subject=SceneSubject(anchorTime:0,rect:NormalizedRect(x:0,y:0,width:1,height:1))
        var settings=EffectSettings();settings.scene=SceneSettings(subjects:[subject]);settings.add("waistDefine",target:"subject",subjectID:subject.id)
        let body=BodyGeometry(joints:["ls":CGPoint(x:0.3,y:0.85),"rs":CGPoint(x:0.7,y:0.85),"lh":CGPoint(x:0.38,y:0.35),"rh":CGPoint(x:0.62,y:0.35)])
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:EffectsAnalysis(personMask:CIImage(color:.white).cropped(to:e),bodies:[body]))
        XCTAssertEqual(pixel(image,x:78,y:68),pixel(output,x:78,y:68))
    }
    func testNamedBackgroundKeepsItsSubjectInsteadOfPaintingOverIt() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.4,blue:0.5)).cropped(to:e)
        var settings=EffectSettings();settings.add("blackStudio",target:"subject",subjectID:UUID())
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:EffectsAnalysis(personMask:CIImage(color:.white).cropped(to:e)))
        XCTAssertEqual(pixel(image),pixel(output))
    }
    func testFallbackRegistrationMeasuresKnownTranslation() throws {
        let image=try fixture();let old=try SceneModels.raster(image,edge:192)
        let ci=CIImage(cgImage:old)
        let shifted=ci.transformed(by:CGAffineTransform(translationX:8,y:-4)).composited(over:CIImage(color:.black).cropped(to:ci.extent)).cropped(to:ci.extent)
        let current=try SceneModels.raster(shifted,edge:192)
        let delta=SceneOpticalFlow.translation(from:old,to:current)
        XCTAssertEqual(delta.x*192,8,accuracy:2.1);XCTAssertEqual(delta.y*192,-4,accuracy:2.1)
    }
    func testMaskBoundsPreserveRealForegroundCoordinates() throws {
        let mask=CIImage(color:.white).cropped(to:CGRect(x:32,y:64,width:48,height:32)).composited(over:CIImage(color:.black).cropped(to:e))
        let b=try PromptSelection.bounds(of:mask)
        XCTAssertEqual(b.x,0.25,accuracy:0.015);XCTAssertEqual(b.y,0.25,accuracy:0.015)
        XCTAssertEqual(b.width,0.375,accuracy:0.015);XCTAssertEqual(b.height,0.25,accuracy:0.015)
    }

    func testTensorPlaneUsesTopFirstRowsExactlyOnce() throws {
        let a=try MLMultiArray(shape:[1,1,4,4],dataType:.float32)
        for i in 0..<a.count {a[i]=0}
        a[[0,0,1,0]]=1
        let image=try SceneModels.plane(a)
        XCTAssertGreaterThan(pixel(image,x:0,y:2)[0],250)
        XCTAssertLessThan(pixel(image,x:0,y:1)[0],5)
    }
    func testSAMBoxSelectsWholeForeground() throws {
        let image=try fixture(),id=UUID()
        let box=NormalizedRect(x:0.02,y:0.02,width:0.72,height:0.96)
        let masks=try PromptSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.42,y:0.32),SelectionPoint(x:0.25,y:0.55)],box:box)])
        let mask=try XCTUnwrap(masks[id]),bounds=try PromptSelection.bounds(of:mask)
        XCTAssertGreaterThan(bounds.width,0.25);XCTAssertGreaterThan(bounds.height,0.45)
        XCTAssertLessThan(pixel(mask,x:480,y:480)[0],100)
        try write(mask,"sam-full-subject")
    }
    func testMotionFallbackDoesNotInventFlatSceneMovement() throws {
        let image=CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5)).cropped(to:e),cg=try SceneModels.raster(image,edge:128)
        XCTAssertEqual(SceneOpticalFlow.translation(from:cg,to:cg),.zero)
    }

}
