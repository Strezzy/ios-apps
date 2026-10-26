from pathlib import Path
p=Path('Loop/App/Creative/SubjectPickerView.swift');s=p.read_text()
s=s.replace('import ImageIO\n','import ImageIO\n@preconcurrency import AVFoundation\n',1)
old='}.frame(height:360).accessibilityIdentifier("subjectPickerCanvas")'
new='''}.frame(height:360)
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel("Subject selection canvas")
                        .accessibilityValue(source == nil ? "Loading video frame" : "Video frame ready")
                        .accessibilityHint("Tap the person or object to select it, then use Keep or Remove for corrections.")
                        .accessibilityIdentifier("subjectPickerCanvas")'''
assert s.count(old)==1;s=s.replace(old,new)
old='''                    preview.stop();source=preview.sourceFrame
                    if let subject='''
new='''                    preview.stop();source=preview.sourceFrame
                    if source == nil {
                        do {
                            let generator=MediaEngine.makeGenerator(url:store.sourceURL(project),maximumDimension:960)
                            defer {generator.cancelAllCGImageGeneration()}
                            source=try await generator.image(at:CMTime(seconds:preview.displayedTime,preferredTimescale:60_000)).image
                        } catch {self.error="This frame could not be loaded. Close the sheet and move the playhead."}
                    }
                    if let subject='''
assert s.count(old)==1;s=s.replace(old,new);p.write_text(s)
p=Path('Loop/UITests/CreativeUITests.swift');s=p.read_text()
old='''        XCTAssertTrue(app.otherElements["subjectPickerCanvas"].waitForExistence(timeout:10))'''
new='''        let canvas=app.descendants(matching:.any)["subjectPickerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout:15))
        XCTAssertEqual(canvas.value as? String,"Video frame ready")'''
assert s.count(old)==1;s=s.replace(old,new);p.write_text(s)
print('Selection accessibility and frame-loading recovery applied.')
