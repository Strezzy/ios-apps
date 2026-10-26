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

p = Path('Loop/Tests/CreativeTests.swift')
s = p.read_text()
pos = s.rfind('\n}')
assert pos > 0
s = s[:pos] + '''
    func testMissingSelectedSubjectNeverExportsAllPeople() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.4,blue:0.5)).cropped(to:e)
        let people=CIImage(color:.white).cropped(to:e)
        var settings=EffectSettings();settings.scene=SceneSettings(selectedID:UUID())
        let analysis=EffectsAnalysis(personMask:people)
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:analysis,transparent:true)
        XCTAssertEqual(pixel(output)[3],0,"A missing selected subject must not fall back to all people.")
    }
    func testMissingSelectedBodyMaskLeavesFrameUnchanged() throws {
        let image=CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:128,y:0),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:e)
        let subject=SceneSubject(anchorTime:0,rect:NormalizedRect(x:0,y:0,width:1,height:1))
        var settings=EffectSettings();settings.scene=SceneSettings(subjects:[subject]);settings.add("waistDefine",target:"subject",subjectID:subject.id)
        let body=BodyGeometry(joints:["ls":CGPoint(x:0.3,y:0.85),"rs":CGPoint(x:0.7,y:0.85),"lh":CGPoint(x:0.38,y:0.35),"rh":CGPoint(x:0.62,y:0.35)])
        let analysis=EffectsAnalysis(personMask:CIImage(color:.white).cropped(to:e),bodies:[body])
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:analysis)
        XCTAssertEqual(pixel(image,x:78,y:68),pixel(output,x:78,y:68))
    }
    func testNamedBackgroundKeepsItsSubjectInsteadOfPaintingOverIt() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.4,blue:0.5)).cropped(to:e)
        var settings=EffectSettings();settings.add("blackStudio",target:"subject",subjectID:UUID())
        let output=try RealismCompositor.apply(image,settings:settings,time:1,preview:false,analysis:EffectsAnalysis(personMask:CIImage(color:.white).cropped(to:e)))
        XCTAssertEqual(pixel(image),pixel(output),"No named mask means no replacement, not a fallback to another subject.")
    }
''' + s[pos:]
p.write_text(s)
print('Selected-subject rendering is guarded, with targeted regression tests.')
