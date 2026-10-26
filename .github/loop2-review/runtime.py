from pathlib import Path

p=Path('Loop/Core/Creative/SceneInference.swift')
s=p.read_text()
old='let configuration=MLModelConfiguration();configuration.computeUnits = .all'
assert s.count(old)==1
s=s.replace(old,'''let configuration=MLModelConfiguration()
        // SAM's variable prompt shapes follow the upstream CPU/GPU execution path.
        configuration.computeUnits = name.hasPrefix("SAM2") ? .cpuAndGPU : .all''')
s=s.replace('            if coordinates.count==1 {coordinates.append((0,0,-1))}', '''            // The bundled prompt encoder already adds its own no-point token.''')
old='''        var bytes=[UInt8](repeating:0,count:w*h)
        SceneModels.context.render(small,toBitmap:&bytes,rowBytes:w,bounds:small.extent,format:.L8,colorSpace:nil)'''
new='''        var rgba=[UInt8](repeating:0,count:w*h*4)
        SceneModels.context.render(small,toBitmap:&rgba,rowBytes:w*4,bounds:small.extent,format:.RGBA8,colorSpace:SceneModels.rgb)
        let bytes=stride(from:0,to:rgba.count,by:4).map{rgba[$0]}'''
assert s.count(old)==1;s=s.replace(old,new)
start=s.index('enum SceneOpticalFlow {')
s=s[:start]+r'''/// Dense Vision flow is preferred. Some OS installations do not include its
/// neural weights; bounded translation alignment keeps preview/export usable.
enum SceneOpticalFlow {
    private static let capabilityLock=NSLock()
    private static var denseUnavailable=false
    static func warp(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)throws->CIImage {
        capabilityLock.lock();let available = !denseUnavailable;capabilityLock.unlock()
        if available {
            do {
                let request=VNGenerateOpticalFlowRequest(targetedCGImage:old,options:[:])
                request.computationAccuracy = .medium
                request.outputPixelFormat=kCVPixelFormatType_TwoComponent32Float
                try VNImageRequestHandler(cgImage:current,orientation:.up,options:[:]).perform([request])
                if let buffer=request.results?.first?.pixelBuffer {
                    let flow=SceneModels.fit(CIImage(cvPixelBuffer:buffer),to:extent)
                    return try RealismKernels.general("loopFlowAlign",extent:extent,arguments:[SceneModels.fit(mask,to:extent).clampedToExtent(),flow,CIVector(x:extent.width/CGFloat(current.width),y:extent.height/CGFloat(current.height))],padding:max(extent.width,extent.height)*0.2)
                }
            } catch {
                // Do not repeatedly ask Vision for an estimator that the OS cannot create.
                let failure=error as NSError
                if failure.domain==VNErrorDomain && failure.code==9 {
                    capabilityLock.lock();denseUnavailable=true;capabilityLock.unlock()
                }
            }
        }
        return translationFallback(mask,from:old,to:current,extent:extent)
    }
    static func translationFallback(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)->CIImage {
        let offset=translationOffset(from:old,to:current)
        let shifted=SceneModels.fit(mask,to:extent).transformed(by:CGAffineTransform(translationX:offset.x*extent.width, y:offset.y*extent.height))
        return shifted.composited(over:CIImage(color:.black).cropped(to:extent)).cropped(to:extent)
    }
    /// Normalized image-plane translation, not a substitute for dense scene flow.
    static func translationOffset(from old:CGImage,to current:CGImage)->CGPoint {
        let side=64,margin=10,radius=8
        func pixels(_ image:CGImage)->[Float] {
            var rgba=[UInt8](repeating:0,count:side*side*4)
            let small=SceneModels.fit(CIImage(cgImage:image),to:CGRect(x:0,y:0,width:side,height:side))
            SceneModels.context.render(small,toBitmap:&rgba,rowBytes:side*4,bounds:small.extent,format:.RGBA8,colorSpace:SceneModels.rgb)
            return stride(from:0,to:rgba.count,by:4).map{(Float(rgba[$0])*.2126+Float(rgba[$0+1])*.7152+Float(rgba[$0+2])*.0722)/255}
        }
        let before=pixels(old),now=pixels(current)
        let mean=now.reduce(0,+)/Float(now.count)
        let variance=now.reduce(Float(0)){$0+($1-mean)*($1-mean)}/Float(now.count)
        guard variance>0.0001 else{return .zero}
        func cost(_ dx:Int,_ dy:Int)->Double {
            var sum=Double(0)
            for y in margin..<(side-margin) {for x in margin..<(side-margin) {
                let difference=Double(now[y*side+x]-before[(y-dy)*side+x-dx])
                sum+=difference*difference
            }}
            return sum/Double((side-2*margin)*(side-2*margin))
        }
        let zero=cost(0,0)
        guard zero>0.0000001 else{return .zero}
        var best=zero,bx=0,by=0
        for y in -radius...radius {for x in -radius...radius {
            let value=cost(x,y)
            if value<best {best=value;bx=x;by=y}
        }}
        guard best<zero*0.9 else{return .zero}
        func refined(_ negative:Double,_ middle:Double,_ positive:Double)->CGFloat {
            let denominator=negative-2*middle+positive
            guard denominator>0.000001 else{return 0}
            return CGFloat(max(-0.5,min(0.5,0.5*(negative-positive)/denominator)))
        }
        let dx=abs(bx)<radius ? refined(cost(bx-1,by),best,cost(bx+1,by)):0
        let dy=abs(by)<radius ? refined(cost(bx,by-1),best,cost(bx,by+1)):0
        return CGPoint(x:(CGFloat(bx)+dx)/CGFloat(side),y:(CGFloat(by)+dy)/CGFloat(side))
    }
}
'''
# Swift requires a leading zero after an operator to disambiguate a float literal.
s=s.replace(')*.2126',')*0.2126').replace(')*.7152',')*0.7152').replace(')*.0722',')*0.0722')
p.write_text(s)

p=Path('Loop/Tests/CreativeTests.swift');s=p.read_text()
old='XCTAssertGreaterThan(bounds.width,0.1);try write(mask,"sam-subject")'
assert s.count(old)==1
s=s.replace(old,'XCTAssertGreaterThan(bounds.width,0.005);XCTAssertTrue(bounds.cgRect.insetBy(dx:-0.02,dy:-0.02).contains(CGPoint(x:0.5,y:0.65)));try write(mask,"sam-detail")')
pos=s.rfind('\n}')
s=s[:pos]+r'''
    func testSAMBoxSelectsWholeForeground() throws {
        let image=try fixture(),id=UUID()
        let box=NormalizedRect(x:0.02,y:0.02,width:0.72,height:0.96)
        let masks=try PromptSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.42,y:0.32),SelectionPoint(x:0.25,y:0.55)],box:box)])
        let mask=try XCTUnwrap(masks[id]),bounds=try PromptSelection.bounds(of:mask)
        XCTAssertGreaterThan(bounds.width,0.25);XCTAssertGreaterThan(bounds.height,0.45)
        XCTAssertLessThan(pixel(mask,x:480,y:480)[0],100)
        try write(mask,"sam-subject")
    }
    func testMaskBoundsReadbackAndOrientation() throws {
        let mask=CIImage(color:.white).cropped(to:CGRect(x:32,y:64,width:64,height:32)).composited(over:CIImage(color:.black).cropped(to:e))
        let b=try PromptSelection.bounds(of:mask)
        XCTAssertEqual(b.x,0.25,accuracy:0.02);XCTAssertEqual(b.y,0.25,accuracy:0.02)
        XCTAssertEqual(b.width,0.5,accuracy:0.02);XCTAssertEqual(b.height,0.25,accuracy:0.02)
    }
    func testMotionFallbackTracksKnownTranslation() throws {
        let image=try fixture(),old=try SceneModels.raster(image,edge:128)
        let base=CIImage(cgImage:old),bounds=base.extent
        let moved=base.transformed(by:CGAffineTransform(translationX:6,y:4)).composited(over:CIImage(color:.black).cropped(to:bounds)).cropped(to:bounds)
        let current=try SceneModels.raster(moved,edge:128)
        let offset=SceneOpticalFlow.translationOffset(from:old,to:current)
        XCTAssertEqual(offset.x*128,6,accuracy:1.2);XCTAssertEqual(offset.y*128,4,accuracy:1.2)
        let mask=CIImage(color:.white).cropped(to:CGRect(x:32,y:48,width:32,height:32)).composited(over:CIImage(color:.black).cropped(to:bounds))
        let aligned=SceneOpticalFlow.translationFallback(mask,from:old,to:current,extent:bounds)
        XCTAssertLessThan(pixel(aligned,x:33,y:64)[0],30)
        XCTAssertGreaterThan(pixel(aligned,x:67,y:64)[0],220)
    }
    func testMotionFallbackDoesNotInventFlatSceneMovement() throws {
        let image=CIImage(color:.gray).cropped(to:e),cg=try SceneModels.raster(image,edge:128)
        XCTAssertEqual(SceneOpticalFlow.translationOffset(from:cg,to:cg),.zero)
    }
''' + s[pos:]
p.write_text(s)
for name in ['Loop/docs/CREATIVE-RESEARCH.md','Loop/docs/RELEASE.md']:
 p=Path(name);s=p.read_text();s+='\n\n### Motion-analysis availability\nVision dense optical flow is used where the operating system can initialize its estimator. If it is unavailable, Loop uses bounded image-plane translation alignment with motion-gated blending instead of failing the edit. Translation fallback is not dense flow or 3D reconstruction. Fine-detail SAM taps can select clothing details or small objects; additional foreground/background points refine the selection.\n';p.write_text(s)
print('Runtime model execution, mask readback and motion fallback hardened.')
