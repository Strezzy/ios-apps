import XCTest
import CoreImage
import CoreVideo
import VideoToolbox
@preconcurrency import AVFoundation
@testable import Loop

final class CreativeExportTests: XCTestCase {
    private let context=CIContext(options:[.cacheIntermediates:false])
    private var folder:URL!
    override func setUpWithError() throws {
        folder=FileManager.default.temporaryDirectory.appendingPathComponent("LoopCreativeExports-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws {try? FileManager.default.removeItem(at:folder);FrameRenderer.clearCaches()}
    private func fixture() throws -> CIImage {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"portrait-fixture",withExtension:"png"))
        return try XCTUnwrap(CIImage(contentsOf:url)).transformed(by:CGAffineTransform(scaleX:0.5,y:0.5))
    }
    private func makeSource(hdr:Bool=false) async throws -> URL {
        let url=folder.appendingPathComponent(UUID().uuidString+".mov")
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        var compression:[String:Any]=[AVVideoAllowFrameReorderingKey:false]
        var settings:[String:Any]=[AVVideoCodecKey:hdr ? AVVideoCodecType.hevc:AVVideoCodecType.h264,AVVideoWidthKey:256,AVVideoHeightKey:256]
        if hdr {
            compression[AVVideoProfileLevelKey]=kVTProfileLevel_HEVC_Main10_AutoLevel
            settings[AVVideoColorPropertiesKey]=[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_2020,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_2100_HLG,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_2020]
        }
        settings[AVVideoCompressionPropertiesKey]=compression
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:settings)
        let pixelFormat=hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:kCVPixelFormatType_32BGRA
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:pixelFormat,kCVPixelBufferWidthKey as String:256,kCVPixelBufferHeightKey as String:256,kCVPixelBufferIOSurfacePropertiesKey as String:[:]])
        XCTAssertTrue(writer.canAdd(input));writer.add(input)
        guard writer.startWriting() else{throw writer.error ?? LoopError.encoding("Source encoder unavailable")}
        writer.startSession(atSourceTime:.zero)
        let portrait=try fixture(),extent=CGRect(x:0,y:0,width:256,height:256)
        let space=CGColorSpace(name:hdr ? CGColorSpace.itur_2100_HLG:CGColorSpace.sRGB)!
        for i in 0..<6 {
            let start=Date()
            while !input.isReadyForMoreMediaData {
                if let error=writer.error{throw error}
                guard Date().timeIntervalSince(start)<15 else{throw LoopError.encoding("Source writer timed out")}
                try await Task.sleep(nanoseconds:2_000_000)
            }
            let pool=try XCTUnwrap(adaptor.pixelBufferPool);var value:CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,pool,&value),kCVReturnSuccess)
            let buffer=try XCTUnwrap(value)
            let stripeColor=try XCTUnwrap(CIColor(red:hdr ? 3:1,green:hdr ? 2:0.5,blue:0.2,alpha:1,colorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!))
            let stripe=CIImage(color:stripeColor).cropped(to:CGRect(x:5+i*3,y:5,width:15,height:15))
            context.render(stripe.composited(over:portrait).cropped(to:extent),to:buffer,bounds:extent,colorSpace:space)
            XCTAssertTrue(adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(i),timescale:6)))
        }
        writer.endSession(atSourceTime:CMTime(seconds:1,preferredTimescale:60000));input.markAsFinished();await writer.finishWriting()
        guard writer.status == .completed else{throw writer.error ?? LoopError.encoding("Fixture did not finish")}
        return url
    }
    private func project(_ url:URL) async throws -> LoopProject {
        var p=LoopProject(name:"Creative export",sourceFilename:url.lastPathComponent,metadata:try await MediaEngine.inspect(url:url))
        p.export.maximumDimension=256;p.export.frameRate=6;p.export.includeAudio=false
        return p
    }
    func testMP4EffectTimingAndSeamActuallyExport() async throws {
        let source=try await makeSource();var p=try await project(source);p.export.format = .mp4
        p.motion=MotionSettings(seamBlend:0.15)
        var effects=EffectSettings();effects.add("noir");effects.tracks?[0].fadeIn=0.2;p.effects=effects
        let output=folder.appendingPathComponent("seam.mp4")
        let result=try await VideoFileExporter.export(sourceURL:source,project:p,destination:output,control:ExportControl(),progress:{_ in})
        XCTAssertEqual(result.duration,0.85,accuracy:0.02);XCTAssertGreaterThan(result.byteCount,1000)
        let generator=MediaEngine.makeGenerator(url:output,maximumDimension:256)
        let image=try await generator.image(at:CMTime(seconds:0.5,preferredTimescale:60000)).image
        XCTAssertEqual(image.width,256)
    }
    func testHEVCAlphaExportRetainsTransparency() async throws {
        let source=try await makeSource();var p=try await project(source);p.export.format = .hevcAlpha
        let output=folder.appendingPathComponent("cutout.mov")
        _ = try await VideoFileExporter.export(sourceURL:source,project:p,destination:output,control:ExportControl(),progress:{_ in})
        let asset=AVURLAsset(url:output),tracks=try await asset.loadTracks(withMediaType:.video)
        let track=try XCTUnwrap(tracks.first),formats=try await track.load(.formatDescriptions)
        let format=try XCTUnwrap(formats.first)
        let extensions=try XCTUnwrap(CMFormatDescriptionGetExtensions(format)) as NSDictionary
        XCTAssertEqual((extensions[kCMFormatDescriptionExtension_ContainsAlphaChannel] as? NSNumber)?.boolValue,true)
        let generator=MediaEngine.makeGenerator(url:output,maximumDimension:256)
        let image=CIImage(cgImage:try await generator.image(at:CMTime(seconds:0.3,preferredTimescale:60000)).image)
        var pixel=[UInt8](repeating:0,count:4)
        context.render(image,toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:245,y:245,width:1,height:1),format:.RGBA8,colorSpace:SceneModels.rgb)
        XCTAssertLessThan(pixel[3],120,"A background corner must decode with transparency.")
    }
    func testHLGExportRetainsHDRMetadataAndTenBitDecode() async throws {
        let source=try await makeSource(hdr:true);var p=try await project(source)
        XCTAssertTrue(p.metadata.isHDR)
        p.export.format = .hevc;p.export.hdrOutput=true
        let output=folder.appendingPathComponent("hdr.mp4")
        _ = try await VideoFileExporter.export(sourceURL:source,project:p,destination:output,control:ExportControl(),progress:{_ in})
        let metadata=try await MediaEngine.inspect(url:output);XCTAssertTrue(metadata.isHDR)
        let asset=AVURLAsset(url:output),tracks=try await asset.loadTracks(withMediaType:.video)
        let track=try XCTUnwrap(tracks.first),reader=try AVAssetReader(asset:asset)
        let frames=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        reader.add(frames);XCTAssertTrue(reader.startReading())
        let sample=try XCTUnwrap(frames.copyNextSampleBuffer()),buffer=try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer),kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        reader.cancelReading()
    }
    func testCinemagraphFrozenReferenceRendersAndExports() async throws {
        let source=try await makeSource();var p=try await project(source);p.export.format = .mp4
        let generator=MediaEngine.makeGenerator(url:source,maximumDimension:256)
        let still=try await generator.image(at:.zero).image
        let path=try CreativeAssets.save(still,projectID:p.id)
        defer{CreativeAssets.remove(p.id)}
        p.motion=MotionSettings(mode:"moveSubject",referenceTime:0,referenceAsset:path)
        let output=folder.appendingPathComponent("living-photo.mp4")
        _ = try await VideoFileExporter.export(sourceURL:source,project:p,destination:output,control:ExportControl(),progress:{_ in})
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.path))
    }
}
