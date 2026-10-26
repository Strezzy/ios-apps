import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import CoreML
@preconcurrency import Vision

/// Coordinates are normalized, upright and bottom-left, matching Core Image.
struct FaceGeometry: Sendable {
    var bounds: CGRect
    var leftEye: CGPoint
    var rightEye: CGPoint
    var nose: CGPoint
    var mouth: CGPoint
    var contour: [CGPoint]
    var yaw: Double
    init(_ face: VNFaceObservation) {
        let box = face.boundingBox
        bounds = box
        func point(_ region: VNFaceLandmarkRegion2D?, fallback: CGPoint) -> CGPoint {
            guard let region, region.pointCount > 0 else { return fallback }
            let p = region.normalizedPoints.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: box.minX + p.x / CGFloat(region.pointCount) * box.width,
                           y: box.minY + p.y / CGFloat(region.pointCount) * box.height)
        }
        // Initialize stored properties before the local helper captures bounds.
        leftEye = .zero; rightEye = .zero; nose = .zero; mouth = .zero; contour = []; yaw = face.yaw?.doubleValue ?? 0
        leftEye = point(face.landmarks?.leftEye, fallback: CGPoint(x: bounds.minX + bounds.width * 0.3, y: bounds.minY + bounds.height * 0.65))
        rightEye = point(face.landmarks?.rightEye, fallback: CGPoint(x: bounds.minX + bounds.width * 0.7, y: bounds.minY + bounds.height * 0.65))
        if leftEye.x > rightEye.x { let p = leftEye; leftEye = rightEye; rightEye = p }
        nose = point(face.landmarks?.nose, fallback: CGPoint(x: bounds.midX, y: bounds.midY))
        mouth = point(face.landmarks?.outerLips, fallback: CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.24))
        contour = face.landmarks?.faceContour?.normalizedPoints.map {
            CGPoint(x: bounds.minX + $0.x * bounds.width, y: bounds.minY + $0.y * bounds.height)
        } ?? []
    }
    func smoothed(from previous: Self, weight: CGFloat) -> Self {
        var value = self
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x-a.x)*weight, y: a.y + (b.y-a.y)*weight) }
        value.bounds = CGRect(origin: mix(previous.bounds.origin, bounds.origin), size: CGSize(
            width: previous.bounds.width + (bounds.width-previous.bounds.width)*weight,
            height: previous.bounds.height + (bounds.height-previous.bounds.height)*weight))
        value.leftEye = mix(previous.leftEye, leftEye); value.rightEye = mix(previous.rightEye, rightEye)
        value.nose = mix(previous.nose, nose); value.mouth = mix(previous.mouth, mouth)
        if contour.count == previous.contour.count { value.contour = zip(previous.contour, contour).map { mix($0.0,$0.1) } }
        return value
    }
}
struct BodyGeometry: Sendable {
    var joints: [String: CGPoint]
    init(joints: [String: CGPoint]) { self.joints = joints }
    init?(_ observation: VNHumanBodyPoseObservation) {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let names: [(String,VNHumanBodyPoseObservation.JointName)] = [
            ("ls",.leftShoulder),("rs",.rightShoulder),("lh",.leftHip),("rh",.rightHip),
            ("lk",.leftKnee),("rk",.rightKnee),("la",.leftAnkle),("ra",.rightAnkle),
            ("le",.leftElbow),("re",.rightElbow),("lw",.leftWrist),("rw",.rightWrist)]
        joints = Dictionary(uniqueKeysWithValues: names.compactMap { key, name in
            guard let point = points[name], point.confidence >= 0.45 else { return nil }
            return (key, point.location)
        })
        guard joints["ls"] != nil, joints["rs"] != nil, joints["lh"] != nil, joints["rh"] != nil else { return nil }
    }
}

final class RealismSession: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var previousMask: CGImage?
    fileprivate var previousImage: CGImage?
    fileprivate var previousFaces: [FaceGeometry] = []
    fileprivate var previousBodies: [BodyGeometry] = []
    fileprivate var lastTime: Double = -.infinity
    fileprivate var size = CGSize.zero
    fileprivate var signature = ""
    fileprivate var direction = 0.0
    fileprivate var lastAnalysis: EffectsAnalysis?
    fileprivate var personRequest = VNGeneratePersonSegmentationRequest()
    fileprivate func reset() {
        previousMask = nil; previousImage = nil; previousFaces = []; previousBodies = []
        lastAnalysis = nil; direction = 0
        personRequest = VNGeneratePersonSegmentationRequest()
    }
}

enum RealismSessions {
    private static let lock = NSLock()
    private static var sessions: [UUID: RealismSession] = [:]
    static func preview(_ id: UUID) -> RealismSession {
        lock.lock(); defer { lock.unlock() }
        if let existing = sessions[id] { return existing }
        if sessions.count >= 3 { sessions.removeAll() }
        let value = RealismSession(); sessions[id] = value; return value
    }
    static func clear() { lock.lock(); sessions.removeAll(); lock.unlock() }
}

enum RealismKernels {
    private static let data: Result<Data, Error> = Result {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            throw LoopError.encoding("The high-quality effects shaders are missing. Reinstall the complete Loop update.")
        }
        return try Data(contentsOf: url)
    }
    private static let lock = NSLock()
    private static var cached: [String: CIKernel] = [:]
    static func kernel(_ name: String) throws -> CIKernel {
        lock.lock(); defer { lock.unlock() }
        if let existing = cached[name] { return existing }
        let result: CIKernel
        if name == "loopReshape" { result = try CIWarpKernel(functionName: name, fromMetalLibraryData: data.get()) }
        else if ["loopSkinMask","loopRetouch","loopTemporalMatte","loopAgingDetail"].contains(name) {
            result = try CIColorKernel(functionName: name, fromMetalLibraryData: data.get())
        } else { result = try CIKernel(functionName: name, fromMetalLibraryData: data.get()) }
        cached[name] = result; return result
    }
    static func color(_ name: String, extent: CGRect, arguments: [Any]) throws -> CIImage {
        guard let kernel = try kernel(name) as? CIColorKernel,
              let output = kernel.apply(extent: extent, arguments: arguments) else {
            throw LoopError.encoding("The \(name) effect could not render.")
        }
        return output
    }
    static func general(_ name: String, extent: CGRect, arguments: [Any], padding: CGFloat = 12) throws -> CIImage {
        guard let output = try kernel(name).apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -padding, dy: -padding) }, arguments: arguments) else {
            throw LoopError.encoding("The \(name) effect could not render.")
        }
        return output
    }
}

enum LocalPortraitModels {
    private static let lock = NSLock()
    private static var models: [String: MLModel] = [:]
    static let context = CIContext(options: [.cacheIntermediates:false])
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static func predict(_ input: CIImage, name: String) throws -> CIImage {
        lock.lock(); defer { lock.unlock() }
        let model: MLModel
        if let existing = models[name] { model = existing }
        else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
                throw LoopError.encoding("The bundled \(name) model is missing. Install the complete Loop update; no internet download is used.")
            }
            let configuration = MLModelConfiguration(); configuration.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: configuration); models[name] = model
        }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,512,512,kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferCGImageCompatibilityKey:true,
             kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer)
        guard status == kCVReturnSuccess, let buffer else { throw LoopError.encoding("Portrait processing ran out of buffer space.") }
        context.render(input, to: buffer, bounds: CGRect(x:0,y:0,width:512,height:512), colorSpace:srgb)
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary:["image":MLFeatureValue(pixelBuffer:buffer)]))
        guard let output = result.featureValue(for:"output")?.imageBufferValue else { throw LoopError.encoding("The portrait model returned no image.") }
        // Materialize, rather than retaining model-output buffer memory across successive predictions.
        let image = CIImage(cvPixelBuffer:output)
        guard let raster = context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:srgb) else { throw LoopError.encoding("The portrait result could not be read.") }
        return CIImage(cgImage:raster)
    }
}

enum RealismAnalysis {
    static let context = CIContext(options:[.cacheIntermediates:false,.highQualityDownsample:true])
    static let srgb = CGColorSpace(name:CGColorSpace.sRGB)!
    static func raster(_ input: CIImage) throws -> CGImage {
        guard let image = context.createCGImage(input,from:input.extent,format:.RGBA8,colorSpace:srgb) else { throw LoopError.encoding("The analysis image could not be rendered.") }
        return image
    }
    static func analyze(_ input: CIImage, faces: Bool, person: Bool, body: Bool, preview: Bool,
                        time: Double, tuning: MatteTuning, session supplied: RealismSession?) throws -> EffectsAnalysis {
        let session = supplied ?? RealismSession()
        session.lock.lock(); defer { session.lock.unlock() }
        let extent = input.extent
        let signature = "\(faces)-\(person)-\(body)-\(tuning.subject)-\(tuning.quality)-\(tuning.stability)"
        let dt = time-session.lastTime
        if extent.size != session.size || session.signature != signature || !dt.isFinite || abs(dt) > 0.22 || (dt != 0 && session.direction != 0 && dt * session.direction < 0) {
            session.reset()
        } else if abs(dt) < 0.000001, let cached = session.lastAnalysis { return cached }
        session.size = extent.size; session.signature = signature
        if dt != 0 { session.direction = dt > 0 ? 1 : -1 }
        let edge: CGFloat = preview ? 768 : 1024
        let scale = min(1,edge/max(extent.width,extent.height))
        let small = input.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        let source = try raster(small)
        let handler = VNImageRequestHandler(cgImage:source,orientation:.up,options:[:])
        let faceRequest = VNDetectFaceLandmarksRequest()
        let poseRequest = VNDetectHumanBodyPoseRequest()
        var requests: [VNRequest] = []
        if faces { requests.append(faceRequest) }
        if body { requests.append(poseRequest) }
        if !requests.isEmpty { try handler.perform(requests) }
        let observations = Array((faceRequest.results ?? []).filter { $0.confidence >= 0.55 }.prefix(4))
        var geometry = observations.map(FaceGeometry.init)
        var used = Set<Int>()
        for index in geometry.indices {
            let rect = geometry[index].bounds
            let best = session.previousFaces.indices.filter { !used.contains($0) }.max {
                overlap(rect,session.previousFaces[$0].bounds) < overlap(rect,session.previousFaces[$1].bounds)
            }
            if let best, overlap(rect,session.previousFaces[best].bounds) > 0.6 {
                used.insert(best)
                let motion = hypot(rect.midX-session.previousFaces[best].bounds.midX,rect.midY-session.previousFaces[best].bounds.midY)
                let weight = CGFloat(min(1,max(0.4,0.4+motion*35)))
                geometry[index] = geometry[index].smoothed(from:session.previousFaces[best],weight:weight)
            }
        }
        var bodies = (poseRequest.results ?? []).compactMap(BodyGeometry.init)
        // Only associate clearly matching torsos. Never transfer a stale shape to a new person.
        for i in bodies.indices {
            guard let center = bodies[i].joints["lh"], let old = session.previousBodies.min(by: {
                distance($0.joints["lh"] ?? .zero,center)<distance($1.joints["lh"] ?? .zero,center)
            }), let oldCenter = old.joints["lh"], distance(center,oldCenter) < 0.035 else { continue }
            for (key,p) in bodies[i].joints {
                if let q = old.joints[key],distance(p,q)<0.03 { bodies[i].joints[key] = CGPoint(x:q.x*0.25+p.x*0.75,y:q.y*0.25+p.y*0.75) }
            }
        }
        var mask: CIImage?
        if person {
            if tuning.subject == "foreground" {
                let request = VNGenerateForegroundInstanceMaskRequest(); try handler.perform([request])
                if let result = request.results?.first, !result.allInstances.isEmpty {
                    let buffer = try result.generateScaledMaskForImage(forInstances:result.allInstances,from:handler)
                    mask = CIImage(cvPixelBuffer:buffer)
                }
            } else if tuning.quality == "studio" {
                let factor = 512/max(small.extent.width,small.extent.height)
                let fitted = small.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
                let dx = (512-fitted.extent.width)/2,dy = (512-fitted.extent.height)/2
                let padded = fitted.transformed(by:CGAffineTransform(translationX:dx,y:dy))
                    .composited(over:CIImage(color:.black).cropped(to:CGRect(x:0,y:0,width:512,height:512)))
                mask = try LocalPortraitModels.predict(padded,name:"LoopMatte")
                    .cropped(to:CGRect(x:dx,y:dy,width:fitted.extent.width,height:fitted.extent.height))
                    .transformed(by:CGAffineTransform(translationX:-dx,y:-dy))
            } else {
                session.personRequest.qualityLevel = .accurate
                session.personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
                try handler.perform([session.personRequest])
                if let buffer = session.personRequest.results?.first?.pixelBuffer { mask = CIImage(cvPixelBuffer:buffer) }
            }
            if let found = mask {
                let smallExtent = small.extent
                var scaled = found.transformed(by:CGAffineTransform(scaleX:smallExtent.width/found.extent.width,y:smallExtent.height/found.extent.height)).cropped(to:smallExtent)
                if let previousMask = session.previousMask,let previousImage = session.previousImage,
                   previousMask.width == source.width, previousMask.height == source.height {
                    scaled = try RealismKernels.color("loopTemporalMatte",extent:smallExtent,arguments:[scaled,CIImage(cgImage:previousMask),CIImage(cgImage:source),CIImage(cgImage:previousImage),tuning.stability])
                }
                session.previousMask = try raster(scaled)
                session.previousImage = source
                mask = scaled.transformed(by:CGAffineTransform(scaleX:extent.width/smallExtent.width,y:extent.height/smallExtent.height)).cropped(to:extent)
            } else {
                // No foreground means no stale silhouette from a previous frame.
                session.previousMask = nil; session.previousImage = nil
                mask = CIImage(color:.black).cropped(to:extent)
            }
        }
        let result = EffectsAnalysis(faces:observations,personMask:mask,geometry:geometry,bodies:bodies)
        session.previousFaces = geometry; session.previousBodies = bodies
        session.lastTime = time; session.lastAnalysis = result
        return result
    }
    static func refined(_ mask: CIImage, image: CIImage, tuning: MatteTuning) throws -> CIImage {
        try RealismKernels.general("loopRefineMatte",extent:image.extent,
            arguments:[mask.clampedToExtent(),image.clampedToExtent(),CIVector(x:max(0.7,image.extent.width/1800),y:max(0.7,image.extent.height/1800)),tuning.edge,tuning.feather],padding:8)
    }
    private static func overlap(_ a:CGRect,_ b:CGRect)->CGFloat {
        let i=a.intersection(b); if i.isNull{return 0}
        return i.width*i.height/max(0.0001,a.width*a.height+b.width*b.height-i.width*i.height)
    }
    private static func distance(_ a:CGPoint,_ b:CGPoint)->CGFloat {hypot(a.x-b.x,a.y-b.y)}
}
