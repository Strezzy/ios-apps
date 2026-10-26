from pathlib import Path

def replace(path, old, new):
    p=Path(path);s=p.read_text()
    assert s.count(old)==1,(path,old[:80],s.count(old))
    p.write_text(s.replace(old,new))

replace('Loop/App/Creative/SubjectPickerView.swift',
    '.frame(height:360).accessibilityIdentifier("subjectPickerCanvas")',
    '.frame(height:360).accessibilityElement(children:.ignore).accessibilityLabel("Subject selection canvas").accessibilityHint("Use Choose to select a subject, or Keep and Remove to repair its edge.").accessibilityIdentifier("subjectPickerCanvas")')
replace('Loop/App/Creative/CreativeToolsView.swift',
    'label:{Image(systemName:"plus.circle")}.accessibilityLabel("Choose a subject")',
    'label:{Label("Choose",systemImage:"plus.circle")}.accessibilityLabel("Choose a subject").accessibilityIdentifier("chooseSubject")')
p=Path('Loop/UITests/CreativeUITests.swift');s=p.read_text()
s=s.replace('app.buttons["Choose a subject"]','app.buttons["chooseSubject"]')
s=s.replace('''        XCTAssertTrue(app.otherElements["subjectPickerCanvas"].waitForExistence(timeout:10))''', '''        XCTAssertTrue(app.navigationBars["Choose subject"].waitForExistence(timeout:10))
        capture("Loop2-Subject-Sheet",app)
        let hierarchy=XCTAttachment(string:app.debugDescription);hierarchy.name="Subject-picker-accessibility";hierarchy.lifetime = .keepAlways;add(hierarchy)
        XCTAssertTrue(app.descendants(matching:.any)["subjectPickerCanvas"].waitForExistence(timeout:10))''')
p.write_text(s)
p=Path('Loop/Core/Creative/SceneInference.swift');s=p.read_text()
old='''            let f=array[indices].floatValue
            let v=f.isFinite ? f:0'''
new='''            let f=array[indices].floatValue
            if logits && !f.isFinite {throw LoopError.encoding("The selection model returned invalid numerical values.")}
            let v=f.isFinite ? f:0'''
assert s.count(old)==1;s=s.replace(old,new);p.write_text(s)
for path in ['Loop/docs/RELEASE.md','Loop/docs/CREATIVE-RESEARCH.md']:
 p=Path(path);s=p.read_text();s+='\n\n### Selection-model numerical compatibility\nThe bundled SAM2 mask decoder has one algebraically equivalent local graph change: `pow(x, 2)` is expressed as `mul(x, x)`. Learned weights are unchanged. Both original and patched graph hashes and the unchanged weight hash are recorded in `SCENE-MODELS.json`; `scripts/patch_sam_square.py` reproduces the transform. The native release tests must validate real subject masks before publication. Nonfinite model outputs are rejected, never converted into a whole-frame selection.\n';p.write_text(s)
print('Subject canvas accessibility and numerical-output validation updated.')
