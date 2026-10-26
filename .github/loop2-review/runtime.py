from pathlib import Path

# scope.py supplies the runtime fallback and compact SAM prompt contract.
# These final corrections follow actual native Core Image coordinate probes:
# bitmapData and render(toBitmap:) both use top-first rows, while CI points use
# bottom-left coordinates. Do not flip a tensor image a second time.
p=Path('Loop/Core/Creative/SceneInference.swift');s=p.read_text()
assert 'static func translation(from old:CGImage,to current:CGImage)' in s
old='return raw.transformed(by:CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:CGFloat(h)))'
assert s.count(old)==1
s=s.replace(old,'return raw')
s=s.replace('/// Tensor planes are top-left; CI image construction is flipped explicitly.','/// Tensor planes and CI bitmapData are both top-first; CI handles the coordinate conversion.')
old='y:Double(h-1-maxY)/Double(h)'
assert s.count(old)==1
s=s.replace(old,'y:Double(minY)/Double(h)')
old='return CGPoint(x:offset.x/CGFloat(w),y:offset.y/CGFloat(h))'
assert s.count(old)==1
s=s.replace(old,'return CGPoint(x:offset.x/CGFloat(w),y:-offset.y/CGFloat(h))')
p.write_text(s)

p=Path('Loop/Tests/CreativeTests.swift');s=p.read_text();pos=s.rfind('\n}');assert pos>0
s=s[:pos]+r'''
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
'''+s[pos:];p.write_text(s)
for name in ['Loop/docs/CREATIVE-RESEARCH.md','Loop/docs/RELEASE.md']:
 p=Path(name);s=p.read_text();s+='\n\n### Coordinate and runtime safeguards\nTensor masks and bitmap readbacks follow Core Image top-first memory rows without duplicate vertical flips. Native regression checks cover known mask positions and translated images. When Vision dense-flow model assets are unavailable, bounded global translation alignment is used; this is not dense non-rigid flow or recovered 3D motion.\n';p.write_text(s)
print('Native-probed mask and motion coordinate conventions applied.')
