from pathlib import Path


def replace_once(path, before, after):
    p = Path(path)
    text = p.read_text()
    assert text.count(before) == 1, (path, before, text.count(before))
    p.write_text(text.replace(before, after, 1))


replace_once(
    'Loop/App/Creative/CreativeToolsView.swift',
    'Button{editID=nil;choosing=true}label:{Image(systemName:"plus.circle")}.accessibilityLabel("Choose a subject")',
    'Button{editID=nil;choosing=true}label:{Label("Choose",systemImage:"plus.circle").font(.subheadline)}.buttonStyle(.glass).accessibilityLabel("Choose a subject").accessibilityIdentifier("chooseSubject")'
)
replace_once(
    'Loop/App/Creative/SubjectPickerView.swift',
    '}.frame(height:360).accessibilityIdentifier("subjectPickerCanvas")',
    '}.frame(height:360).accessibilityElement(children:.contain).accessibilityLabel("Subject selection canvas").accessibilityIdentifier("subjectPickerCanvas")'
)
replace_once(
    'Loop/UITests/CreativeUITests.swift',
    'let choose=app.buttons["Choose a subject"];reveal(choose,in:app);choose.tap()\n        XCTAssertTrue(app.otherElements["subjectPickerCanvas"].waitForExistence(timeout:10))',
    'let choose=app.buttons["chooseSubject"];reveal(choose,in:app);XCTAssertTrue(choose.isHittable);choose.tap()\n        XCTAssertTrue(app.navigationBars["Choose subject"].waitForExistence(timeout:15))\n        capture("Loop2-Subject-Screen",app)\n        XCTAssertTrue(app.descendants(matching:.any)["subjectPickerCanvas"].firstMatch.waitForExistence(timeout:10))'
)
print('Made subject choice discoverable and exposed the selection canvas to accessibility and UI testing.')
