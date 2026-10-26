from pathlib import Path
p=Path('Loop/project.yml');s=p.read_text();s=s.replace("    SWIFT_VERSION: '5.0'", "    SWIFT_VERSION: '5.0'\n    'EXCLUDED_ARCHS[sdk=iphonesimulator*]': x86_64",1);p.write_text(s)
p=Path('Loop/Core/Creative/CreativeAssets.swift')
s=p.read_text()
old='        let prepared=try RealismKernels.color("loopLUTDomain",extent:image.extent,arguments:[image,CIVector(values:lut.domainMin.map(CGFloat.init),count:3),CIVector(values:lut.domainMax.map(CGFloat.init),count:3)])'
new='''        let low = CIVector(x: CGFloat(lut.domainMin[0]), y: CGFloat(lut.domainMin[1]), z: CGFloat(lut.domainMin[2]))
        let high = CIVector(x: CGFloat(lut.domainMax[0]), y: CGFloat(lut.domainMax[1]), z: CGFloat(lut.domainMax[2]))
        let prepared = try RealismKernels.color("loopLUTDomain", extent: image.extent, arguments: [image, low, high])'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
p=Path('Loop/Core/Creative/CreativeModels.swift');s=p.read_text()
s=s.replace('var value=old;value.layers=[];value.tracks=[];value.bypass=false','var value=old;value.layers=[];value.tracks=[];value.bypass=false;value.faceTuning=nil;value.bodyTuning=nil;value.lut=nil;value.backdropTuning=nil')
s=s.replace('scene.depthEnabled=true;scene.depthFog=0;scene.relight=0.15;scene.matchLighting=0.3','scene.depthEnabled=true;scene.depthFog=0;scene.depthBlur=0;scene.focus=0.65;scene.lightDirection = -0.5;scene.relight=0.15;scene.matchLighting=0.3')
p.write_text(s)
p=Path('Loop/App/Creative/CreativeToolsView.swift');s=p.read_text()
s=s.replace('}.font(.subheadline)\n            }\n            DisclosureGroup("My effect mix', '}.font(.subheadline).accessibilityIdentifier("sceneAdvanced")\n            }\n            DisclosureGroup("My effect mix')
s=s.replace('}.font(.subheadline.weight(.medium)).padding(.horizontal,4)','}.font(.subheadline.weight(.medium)).padding(.horizontal,4).accessibilityIdentifier("effectMixDisclosure")')
p.write_text(s)
p=Path('Loop/App/ExportOptionsView.swift');s=p.read_text()
s=s.replace('}.font(.subheadline.weight(.semibold))','}.font(.subheadline.weight(.semibold)).accessibilityIdentifier("exportAdvanced")
')
p.write_text(s)
p=Path('Loop/scripts/publish.sh');s=p.read_text()
s=s.replace(' Build/FOCUSED-CREATIVE-TESTS.json Build/SCENE-MODELS.json', ' Build/FOCUSED-CREATIVE-TESTS.json Build/FOCUSED-UI-TESTS.json Build/SCENE-MODELS.json')
p.write_text(s)
p=Path('Loop/App/LoopStore.swift');s=p.read_text()
old='''    func deleteProject(_ project: LoopProject) {
        CreativeAssets.remove(project.id)
        guard !isExporting, trackingProgress == nil else { return }'''
new='''    func deleteProject(_ project: LoopProject) {
        guard !isExporting, trackingProgress == nil else { return }'''
assert s.count(old)==1;s=s.replace(old,new)
old='''            try FileManager.default.removeItem(at: projectDirectory(project.id))
            projects.removeAll { $0.id == project.id }'''
new='''            try FileManager.default.removeItem(at: projectDirectory(project.id))
            CreativeAssets.remove(project.id)
            projects.removeAll { $0.id == project.id }'''
assert s.count(old)==1;p.write_text(s.replace(old,new))
Path('Loop/UITests/CreativeUITests.swift').write_text(r'''import XCTest

final class CreativeUITests: XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable{return}
            let scroll=app.scrollViews.firstMatch
            let start=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.88))
            let end=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.28))
            start.press(forDuration:0.04,thenDragTo:end)
        }
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let file=XCTAttachment(screenshot:app.screenshot());file.name=name;file.lifetime = .keepAlways;add(file)
    }
    @MainActor func testSimpleLooksSubjectAndSaveControls() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        let project=app.buttons["project-Coastal motion"]
        XCTAssertTrue(project.waitForExistence(timeout:40));reveal(project,in:app);project.tap()
        XCTAssertTrue(app.otherElements["editorCanvas"].waitForExistence(timeout:20))
        app.buttons["tool-effects"].tap()
        let look=app.buttons["world-winter"];XCTAssertTrue(look.waitForExistence(timeout:10));reveal(look,in:app)
        XCTAssertTrue(look.isHittable);capture("Loop2-Simple-Looks",app)
        XCTAssertFalse(app.switches["Use scene depth"].isHittable,"Advanced depth controls must start collapsed.")
        let choose=app.buttons["Choose a subject"];reveal(choose,in:app);choose.tap()
        XCTAssertTrue(app.otherElements["subjectPickerCanvas"].waitForExistence(timeout:10))
        XCTAssertTrue(app.segmentedControls.buttons["Keep"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Remove"].exists)
        capture("Loop2-Choose-Subject",app);app.navigationBars.buttons["Cancel"].tap()
        let save=app.buttons["tool-export"];reveal(save,in:app);save.tap()
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["fps-24"].isHittable,"Advanced export controls must start collapsed.")
        capture("Loop2-Simple-Save",app)
        let advanced=app.buttons["exportAdvanced"]
        if advanced.exists {reveal(advanced,in:app);advanced.tap()} else {
            let label=app.staticTexts["Size, smoothness & advanced options"];reveal(label,in:app);label.tap()
        }
        let rate=app.buttons["fps-24"];reveal(rate,in:app);XCTAssertTrue(rate.isHittable)
        capture("Loop2-Optional-Details",app)
    }
}
''')
# The review directory is preserved before switching to the latest main branch.
import os
runtime=Path(os.environ['RUNNER_TEMP'])/'loop2-review'/'runtime.py'
text=runtime.read_text().replace('CIImage(color:.gray)', 'CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5))')
exec(compile(text,'review-native-runtime.py','exec'))
