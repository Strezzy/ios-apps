import XCTest
@testable import Rinse
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import AudioToolbox

final class RinseTests: XCTestCase {
    override func setUpWithError() throws { try Workspace.prepare(reset: true) }

    func fixturePhoto(type: UTType = .jpeg, orientation: Int = 6) throws -> URL {
        let url = Workspace.destination(extension: type.preferredFilenameExtension ?? "jpg")
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
            bytesPerRow: 48 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45.1234, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 123.4567, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RINSE_PRIVATE_FIXTURE", kCGImagePropertyTIFFArtist: "PRIVATE_OWNER"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:12 12:34:56", kCGImagePropertyExifUserComment: "PRIVATE_COMMENT"]]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
    func testJPEGRemovesMetadataAndAppliesOrientation() async throws {
        let input = try fixturePhoto()
        let originalHash = try Fingerprint.sha256(input)
        let result = try await RinseEngine.clean(input)
        XCTAssertFalse(result.before.fields.isEmpty)
        XCTAssertTrue(result.after.fields.isEmpty)
        XCTAssertEqual(result.after.mediaDescription, "32 × 48")
        XCTAssertTrue(result.hashChanged)
        XCTAssertEqual(try Fingerprint.sha256(input), originalHash)
        let data = try Data(contentsOf: result.output)
        XCTAssertNil(data.range(of: Data("RINSE_PRIVATE_FIXTURE".utf8)))
    }
    func testPNGHasUniqueFingerprintsWithoutPixelChanges() async throws {
        let input = try fixturePhoto(type: .png, orientation: 1)
        var options = CleanOptions(); options.photoFormat = .png
        let first = try await RinseEngine.clean(input, options: options)
        let second = try await RinseEngine.clean(input, options: options)
        XCTAssertNotEqual(first.cleanedHash, second.cleanedHash)
        XCTAssertEqual(first.after.mediaDescription, second.after.mediaDescription)
        func raster(_ url: URL) throws -> Data {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try XCTUnwrap(image.dataProvider?.data) as Data
        }
        XCTAssertEqual(try raster(first.output), try raster(second.output))
        XCTAssertTrue(first.after.fields.isEmpty)
    }
    func testHEICRoundTrip() async throws {
        let input = try fixturePhoto(type: .heic, orientation: 1)
        let result = try await RinseEngine.clean(input)
        XCTAssertTrue(result.after.fields.isEmpty)
        XCTAssertTrue(result.hashChanged)
        XCTAssertEqual(result.output.pathExtension, "heic")
    }
    func testPNGWithoutFingerprintPadding() async throws {
        let input = try fixturePhoto(type: .png, orientation: 1)
        var options = CleanOptions(); options.photoFormat = .png; options.freshFingerprint = false
        let result = try await RinseEngine.clean(input, options: options)
        XCTAssertTrue(result.after.fields.isEmpty)
        XCTAssertNil(try Data(contentsOf: result.output).range(of: Data("riNs".utf8)))
    }
    func testCorruptInputIsRejected() async throws {
        let input = Workspace.destination(extension: "jpg")
        try Data("not an image".utf8).write(to: input)
        do { _ = try await RinseEngine.clean(input); XCTFail("Corrupt input was exported") } catch {}
    }
    func testExtensionPixelLimitIsEnforced() async throws {
        let input = try fixturePhoto()
        var options = CleanOptions(); options.maxPhotoPixels = 10
        do { _ = try await RinseEngine.clean(input, options: options); XCTFail("Pixel limit was ignored") } catch {}
    }
    func testCancellationIsNotASuccess() async throws {
        let input = try fixturePhoto()
        let task = Task { try await Task.sleep(nanoseconds: 100_000_000); return try await RinseEngine.clean(input) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled job completed") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testCRC32KnownVector() { XCTAssertEqual(Fingerprint.crc32(Data("123456789".utf8)), 0xcbf43926) }

    func movie(withAudio: Bool, frames: Int = 90) async throws -> URL {
        let url = Workspace.destination(extension: "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let location = AVMutableMetadataItem()
        location.identifier = .quickTimeMetadataLocationISO6709
        location.value = "+45.1234-123.4567/" as NSString
        writer.metadata = [location]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        var soundInput: AVAssetWriterInput?
        if withAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            audio.expectsMediaDataInRealTime = false
            writer.add(audio); soundInput = audio
        }
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        var frame = 0, audioSample = 0
        let samples = withAudio ? 44_100 : 0 // Audio intentionally ends before video.
        var videoFinished = false, audioFinished = !withAudio
        while !videoFinished || !audioFinished {
            if !videoFinished && input.isReadyForMoreMediaData {
                if frame == frames { input.markAsFinished(); videoFinished = true }
                else {
                    var buffer: CVPixelBuffer?
                    XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &buffer), kCVReturnSuccess)
                    let pixels = try XCTUnwrap(buffer)
                    CVPixelBufferLockBaseAddress(pixels, [])
                    memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame % 200), CVPixelBufferGetBytesPerRow(pixels) * 48)
                    CVPixelBufferUnlockBaseAddress(pixels, [])
                    XCTAssertTrue(adapter.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
                    frame += 1
                }
            }
            if !audioFinished, let soundInput, soundInput.isReadyForMoreMediaData {
                if audioSample >= samples { soundInput.markAsFinished(); audioFinished = true }
                else {
                    let count = min(1024, samples - audioSample)
                    var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
                    var format: CMAudioFormatDescription?
                    XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
                    var block: CMBlockBuffer?
                    XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 2,
                        blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block), noErr)
                    let memory = try XCTUnwrap(block)
                    XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: memory, offsetIntoDestination: 0, dataLength: count * 2), noErr)
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100),
                        presentationTimeStamp: CMTime(value: Int64(audioSample), timescale: 44_100), decodeTimeStamp: .invalid)
                    var sample: CMSampleBuffer?
                    var bytes = 2
                    XCTAssertEqual(CMSampleBufferCreateReady(allocator: nil, dataBuffer: memory, formatDescription: format,
                        sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                        sampleSizeEntryCount: 1, sampleSizeArray: &bytes, sampleBufferOut: &sample), noErr)
                    XCTAssertTrue(soundInput.append(try XCTUnwrap(sample)))
                    audioSample += count
                }
            }
            if writer.status == .failed { throw writer.error! }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: 30))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
    func countFrames(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output); XCTAssertTrue(reader.startReading())
        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        XCTAssertEqual(reader.status, .completed)
        return count
    }
    func testVideoMetadataAndAllFrames() async throws {
        let input = try await movie(withAudio: false, frames: 90)
        let result = try await RinseEngine.clean(input)
        XCTAssertFalse(result.before.fields.isEmpty)
        XCTAssertTrue(result.after.fields.isEmpty)
        XCTAssertTrue(result.hashChanged)
        let count = try await countFrames(result.output)
        XCTAssertEqual(count, 90)
    }
    func testEarlyAudioEOFKeepsAllVideoFrames() async throws {
        let input = try await movie(withAudio: true, frames: 120)
        let result = try await RinseEngine.clean(input)
        let count = try await countFrames(result.output)
        XCTAssertEqual(count, 120)
        let tracks = try await AVURLAsset(url: result.output).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertTrue(result.after.fields.isEmpty)
    }
}
