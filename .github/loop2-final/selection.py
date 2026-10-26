from pathlib import Path

Path('Loop/Core/Creative/NativeSubjectSelection.swift').write_text(r'''import Foundation
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
''')

p=Path('Loop/Core/Creative/SceneInference.swift');s=p.read_text()
start=s.index('    static func masks(_ image:CIImage,prompts:[Prompt])throws->[UUID:CIImage] {',s.index('enum PromptSelection'))
end=s.index('    private static func inferMasks(',start)
s=s[:start]+r'''    private static var nativeCompatibility=false
    static var compatibilityHint:String? {
        SceneModels.lock.lock();defer{SceneModels.lock.unlock()}
        return nativeCompatibility ? "Using native subject selection for compatibility. Keep and Remove can refine individual details.":nil
    }
    static func masks(_ image:CIImage,prompts:[Prompt])throws->[UUID:CIImage] {
        guard !prompts.isEmpty else{return [:]}
        SceneModels.lock.lock();defer{SceneModels.lock.unlock()}
        if nativeCompatibility {return try NativeSubjectSelection.masks(image,prompts:prompts)}
        do {return try inferMasks(image,prompts:prompts)}
        catch {
            if error is CancellationError {throw error}
            if !SceneModels.samUsesCPU {
                SceneModels.useSafeSAMBackend()
                do {return try inferMasks(image,prompts:prompts)}
                catch {if error is CancellationError {throw error}}
            }
            // Keep the original trained SAM model available on compatible hardware.
            // An unsupported runtime uses another real segmentation engine, never
            // a fabricated box, full-frame gray mask, or an unrelated person.
            nativeCompatibility=true
            #if DEBUG
            print("Loop selection: native instance-mask compatibility backend")
            #endif
            return try NativeSubjectSelection.masks(image,prompts:prompts)
        }
    }
''' + s[end:]
p.write_text(s)

p=Path('Loop/App/Creative/SubjectPickerView.swift');s=p.read_text()
s=s.replace('    @State private var error:String?','    @State private var error:String?\n    @State private var selectionHint:String?')
s=s.replace('                    if let error{Text(error).font(.callout).foregroundStyle(.orange)}','                    if let selectionHint {Text(selectionHint).font(.caption).foregroundStyle(.secondary)}\n                    if let error{Text(error).font(.callout).foregroundStyle(.orange)}')
s=s.replace('guard token==id else{return};mask=result.0;draft.rect=result.1;overlay=result.2;draft.path=[]','guard token==id else{return};mask=result.0;draft.rect=result.1;overlay=result.2;draft.path=[];selectionHint=PromptSelection.compatibilityHint')
p.write_text(s)

p=Path('Loop/Tests/CreativeTests.swift');s=p.read_text()
s=s.replace('func testSAMBoxSelectsWholeForeground()', 'func testSubjectSelectionBoxSelectsWholeForeground()')
s=s.replace('func testSAMSelectsTappedForeground()', 'func testSubjectSelectionSelectsTappedForeground()')
pos=s.rfind('\n}');assert pos>0
s=s[:pos]+r'''
    func testNativeSelectionKeepsTappedPersonAndRejectsBackground() throws {
        let image=try fixture(),id=UUID()
        let result=try NativeSubjectSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.42,y:0.32),SelectionPoint(x:0.94,y:0.05,include:false)],box:nil)])
        let mask=try XCTUnwrap(result[id])
        let bounds=try PromptSelection.bounds(of:mask)
        XCTAssertGreaterThan(bounds.width,0.2);XCTAssertGreaterThan(bounds.height,0.4)
        XCTAssertGreaterThan(pixel(mask,x:220,y:330)[0],150)
        XCTAssertLessThan(pixel(mask,x:480,y:480)[0],60)
        try write(mask,"native-selected-subject")
    }
    func testNativeSelectionRejectsConflictingInstancePoints() throws {
        let image=try fixture(),point=SelectionPoint(x:0.42,y:0.32)
        XCTAssertThrowsError(try NativeSubjectSelection.masks(image,prompts:[.init(id:UUID(),points:[point,SelectionPoint(x:point.x,y:point.y,include:false)],box:nil)]))
    }
    func testInvalidModelNumbersNeverBecomeAFullFrameMask() throws {
        let array=try MLMultiArray(shape:[1,1,4,4],dataType:.float32)
        for i in 0..<array.count {array[i]=NSNumber(value:Float.nan)}
        XCTAssertThrowsError(try SceneModels.plane(array,logits:true))
    }
''' + s[pos:];p.write_text(s)

for path in ['Loop/docs/RELEASE.md','Loop/docs/CREATIVE-RESEARCH.md']:
    p=Path(path);s=p.read_text()
    if '\n\n### Selection-model numerical compatibility' in s:
        s=s.split('\n\n### Selection-model numerical compatibility')[0].rstrip()+'\n'
    s=s.replace('Tap an object with bundled SAM2 selection,','Tap an object with bundled SAM2 selection and a native compatibility fallback,')
    s=s.replace('SAM2 refines its edges at render time.', 'The selected on-device engine refines its edges at render time.')
    s+='''\n\n### Selection compatibility\nThe upstream SAM2 model packages and learned weights remain unchanged. Original packages produce meaningful masks in the native macOS reference check, but the current iOS simulator produces flat mask outputs. Loop rejects flat/nonfinite masks, retries CPU execution once, and then uses Apple Vision foreground-instance selection for that session if necessary. This selects actual instances under the user's taps, not a rectangle, a full-frame mask or all people. The interface discloses the compatibility path. Native selection can group fine parts together; Keep/Remove brush repairs remain available, and conflicting include/exclude points are rejected. The tests verify the end-to-end selection path and native fallback; they do not claim that SAM inference succeeds on every iPhone or simulator. The speculative square-operation graph change was not adopted because it did not resolve the runtime behavior.\n'''
    p.write_text(s)
print('Native instance fallback added without changing upstream SAM models or accepting invalid masks.')
