from pathlib import Path


def replace(path, old, new):
    p = Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:100], s.count(old))
    p.write_text(s.replace(old, new))


p = 'Loop/Core/RealismCompositor.swift'
replace(p, '''        for track in faceTracks {
            let before=surface.image,amount=track.strength(at:time)''', '''        for track in faceTracks {
            // A selected subject must have a current mask. Never retarget to another person.
            if let id=track.subjectID, information.masks[id] == nil {continue}
            guard track.target != "background" else {continue}
            let before=surface.image,amount=track.strength(at:time)''')
replace(p, '''        for track in bodyTracks {
            let before=surface,box=region(track)''', '''        for track in bodyTracks {
            if let id=track.subjectID, information.masks[id] == nil {continue}
            guard track.target != "background" else {continue}
            let before=surface,box=region(track)''')
replace(p, '''            case .background:
                if let mask=surface.mask {''', '''            case .background:
                // A named subject defines what is kept, not where the new background is painted.
                let foreground = track.subjectID.map { information.masks[$0] } ?? surface.mask
                if let mask=foreground {''')
replace(p, '''            if let mask=targetMask(track){image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:before,kCIInputMaskImageKey:mask])}''', '''            if preset.category != .background, let mask=targetMask(track){image=image.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:before,kCIInputMaskImageKey:mask])}''')
replace(p, '''            let mask=scene.selectedID.flatMap{information.masks[$0]} ?? surface.mask ?? CIImage(color:.black).cropped(to:input.extent)''', '''            let empty=CIImage(color:.black).cropped(to:input.extent)
            let mask:CIImage
            if let selected=scene.selectedID {
                mask=information.masks[selected] ?? empty
            } else {
                mask=surface.mask ?? empty
            }''')
p = 'Loop/App/Creative/CreativeToolsView.swift'
replace(p, '''                            Menu("Apply to"){
                                Button("Whole clip"){edit(track.id){$0.subjectID=nil;$0.target="all"}}
                                Button("People"){edit(track.id){$0.subjectID=nil;$0.target="subject"}}
                                Button("Background"){edit(track.id){$0.subjectID=nil;$0.target="background"}}
                                ForEach(settings.scene?.subjects ?? []){subject in Button(subject.name){edit(track.id){$0.subjectID=subject.id;$0.target="subject"}}}
                            }''', '''                            Menu("Apply to"){
                                let category=EffectLibrary.preset(track.preset)?.category
                                Button(category == .background ? "Behind all people" : (category == .face || category == .body ? "All people" : "Whole clip")){edit(track.id){$0.subjectID=nil;$0.target="all"}}
                                if category != .face && category != .body && category != .background {
                                    Button("People"){edit(track.id){$0.subjectID=nil;$0.target="subject"}}
                                    Button("Background"){edit(track.id){$0.subjectID=nil;$0.target="background"}}
                                    if category == .looks || category == .lens {
                                        Button("Hair"){edit(track.id){$0.subjectID=nil;$0.target="hair"}}
                                        Button("Clothing"){edit(track.id){$0.subjectID=nil;$0.target="clothes"}}
                                    }
                                }
                                ForEach(settings.scene?.subjects ?? []){subject in Button(category == .background ? "Behind \\(subject.name)" : subject.name){edit(track.id){$0.subjectID=subject.id;$0.target="subject"}}}
                            }''')
replace(p, '''    private func targetName(_ t:EffectTrack)->String{if let id=t.subjectID{return settings.scene?.subjects.first{$0.id==id}?.name ?? "Missing subject"};return t.target=="all" ? "Whole clip":t.target.capitalized}''', '''    private func targetName(_ t:EffectTrack)->String {
        let category=EffectLibrary.preset(t.preset)?.category
        if let id=t.subjectID {
            let name=settings.scene?.subjects.first{$0.id==id}?.name ?? "Missing subject"
            return category == .background ? "Behind \\(name)" : name
        }
        if category == .background {return "Behind all people"}
        if category == .face || category == .body {return "All people"}
        switch t.target {case "all":return "Whole clip";case "subject":return "People";case "clothes":return "Clothing";default:return t.target.capitalized}
    }''')
p = 'Loop/Core/ExportPlan.swift'
replace(p, '''var used=Set((project.effects?.tracks ?? []).filter { $0.enabled && $0.target != "all" }.compactMap(\.subjectID))''', '''var used=Set((project.effects?.tracks ?? []).filter { $0.enabled }.compactMap(\.subjectID))''')

p = Path('Loop/Core/Creative/SceneInference.swift');s=p.read_text()
s=s.replace('configuration.computeUnits = .all','configuration.computeUnits = name.hasPrefix("SAM2") ? .cpuAndGPU : .all',1)
s=s.replace('            if coordinates.count==1 {coordinates.append((0,0,-1))}\n','')
needle='''            let output=try decoder.prediction(from:MLDictionaryFeatureProvider(dictionary:features))'''
replacement='''            // Prompt outputs may be strided views. Give the decoder a compact
            // token tensor, without adding a second no-point padding token.
            if let a=features["sparse_embedding"]?.multiArrayValue {
                let type=decoder.modelDescription.inputDescriptionsByName["sparse_embedding"]?.multiArrayConstraint?.dataType ?? a.dataType
                let compact=try MLMultiArray(shape:a.shape,dataType:type)
                for i in 0..<a.count {compact[i]=a[i]}
                features["sparse_embedding"]=MLFeatureValue(multiArray:compact)
            }
            let output=try decoder.prediction(from:MLDictionaryFeatureProvider(dictionary:features))'''
assert s.count(needle)==1;s=s.replace(needle,replacement)
# Core Image can render a data mask to RGBA on every supported backend.
s=s.replace('var bytes=[UInt8](repeating:0,count:w*h)\n        SceneModels.context.render(small,toBitmap:&bytes,rowBytes:w,bounds:small.extent,format:.L8,colorSpace:nil)', 'var bytes=[UInt8](repeating:0,count:w*h*4)\n        SceneModels.context.render(small,toBitmap:&bytes,rowBytes:w*4,bounds:small.extent,format:.RGBA8,colorSpace:SceneModels.rgb)')
s=s.replace('where bytes[y*w+x]>128','where bytes[(y*w+x)*4]>128')
# A one-point subject pick gets an optional native object-size cue. Additional
# positive/negative taps still control the model and may select smaller details.
s=s.replace('''            if let b=prompt.box {coordinates += [(b.x,b.y,2),(b.x+b.width,b.y+b.height,3)]}''','''            let hint=prompt.box ?? (prompt.points.count==1 ? initialObjectBox(image,point:prompt.points[0]):nil)
            if let b=hint {coordinates += [(b.x,b.y,2),(b.x+b.width,b.y+b.height,3)]}''')
insert='''    private static func initialObjectBox(_ image:CIImage,point:SelectionPoint)->NormalizedRect? {
        guard point.include else{return nil}
        do {
            let cg=try SceneModels.raster(image,edge:768)
            let handler=VNImageRequestHandler(cgImage:cg,orientation:.up,options:[:])
            let request=VNGenerateForegroundInstanceMaskRequest();try handler.perform([request])
            guard let observation=request.results?.first else{return nil}
            let labels=observation.instanceMask
            CVPixelBufferLockBaseAddress(labels,.readOnly)
            let label:Int
            if let base=CVPixelBufferGetBaseAddress(labels)?.assumingMemoryBound(to:UInt8.self) {
                let w=CVPixelBufferGetWidth(labels),h=CVPixelBufferGetHeight(labels),stride=CVPixelBufferGetBytesPerRow(labels)
                let x=min(w-1,max(0,Int(point.x*Double(w)))),y=min(h-1,max(0,Int(point.y*Double(h))))
                label=Int(base[y*stride+x])
            } else {label=0}
            CVPixelBufferUnlockBaseAddress(labels,.readOnly)
            guard label>0 else{return nil}
            let buffer=try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:label),from:handler)
            let b=try bounds(of:CIImage(cvPixelBuffer:buffer))
            return b.width*b.height>0.01 ? b:nil
        } catch {return nil}
    }
'''
pos=s.index('    static func bounds(of mask:CIImage)');s=s[:pos]+insert+s[pos:]
start=s.index('enum SceneOpticalFlow {')
s=s[:start]+r'''enum SceneOpticalFlow {
    private static let lock = NSLock()
    private static var nativeUnavailable = false
    /// Dense flow is preferred; unavailable OS model assets must not break playback.
    static func warp(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)throws->CIImage {
        lock.lock();defer{lock.unlock()}
        if !nativeUnavailable {
            do {
                let request=VNGenerateOpticalFlowRequest(targetedCGImage:old,options:[:])
                request.computationAccuracy = .medium
                request.outputPixelFormat=kCVPixelFormatType_TwoComponent32Float
                try VNImageRequestHandler(cgImage:current,orientation:.up,options:[:]).perform([request])
                if let buffer=request.results?.first?.pixelBuffer {
                    let flow=SceneModels.fit(CIImage(cvPixelBuffer:buffer,options:[.colorSpace:NSNull()]),to:extent)
                    return try RealismKernels.general("loopFlowAlign",extent:extent,arguments:[SceneModels.fit(mask,to:extent).clampedToExtent(),flow,CIVector(x:extent.width/CGFloat(current.width),y:extent.height/CGFloat(current.height))],padding:max(extent.width,extent.height)*0.2)
                }
            } catch {nativeUnavailable=true}
        }
        return translated(mask,from:old,to:current,extent:extent)
    }
    /// Bounded global translation fallback, not dense deformation. Low-match
    /// frames are left unshifted and the compositor's motion gate rejects them.
    static func translation(from old:CGImage,to current:CGImage)->CGPoint {
        let w=96,h=96,radius=10
        let bounds=CGRect(x:0,y:0,width:w,height:h)
        func luminance(_ source:CGImage)->[UInt8] {
            var bytes=[UInt8](repeating:0,count:w*h*4)
            SceneModels.context.render(SceneModels.fit(CIImage(cgImage:source),to:bounds),toBitmap:&bytes,rowBytes:w*4,bounds:bounds,format:.RGBA8,colorSpace:SceneModels.rgb)
            return (0..<w*h).map{i in UInt8((Int(bytes[i*4])*54+Int(bytes[i*4+1])*183+Int(bytes[i*4+2])*19)/256)}
        }
        let a=luminance(old),b=luminance(current),margin=radius+2
        func error(_ dx:Int,_ dy:Int)->Double {
            var sum=0.0,count=0
            for y in stride(from:margin,to:h-margin,by:3) {for x in stride(from:margin,to:w-margin,by:3) {
                let d=Double(Int(b[y*w+x])-Int(a[(y-dy)*w+x-dx]))/255
                sum+=d*d;count+=1
            }}
            return sum/Double(max(1,count))
        }
        let initial=error(0,0)
        guard initial>0.00001 else{return .zero}
        var best=initial,offset=CGPoint.zero
        for dy in -radius...radius {for dx in -radius...radius {
            let score=error(dx,dy)
            if score<best-0.0000001 {best=score;offset=CGPoint(x:dx,y:dy)}
        }}
        guard best<0.03,best<initial*0.94 else{return .zero}
        return CGPoint(x:offset.x/CGFloat(w),y:offset.y/CGFloat(h))
    }
    static func translated(_ mask:CIImage,from old:CGImage,to current:CGImage,extent:CGRect)->CIImage {
        let delta=translation(from:old,to:current)
        return SceneModels.fit(mask,to:extent).transformed(by:CGAffineTransform(translationX:delta.x*extent.width,y:delta.y*extent.height))
            .composited(over:CIImage(color:.black).cropped(to:extent)).cropped(to:extent)
    }
}
'''
p.write_text(s)

p = Path('Loop/Tests/CreativeTests.swift');s=p.read_text();pos=s.rfind('\n}');assert pos>0
s=s[:pos]+r'''
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
'''+s[pos:];p.write_text(s)
p=Path('Loop/docs/CREATIVE-RESEARCH.md')
s=p.read_text()+'\n## Runtime portability\nSAM2 uses the CPU/GPU compute path and compact prompt tokens; the prompt encoder supplies its own padding token. First-tap selection can use a native foreground-instance bounding-box cue, then SAM2 refines the requested mask. Dense Vision optical flow is preferred when its OS model is available; a bounded, confidence-gated global translation estimator is the fallback. This fallback does not recover non-rigid pixel motion.\n'
p.write_text(s)
print('Selected-subject guards, prompt layouts and motion fallback integrated.')
