from pathlib import Path
p=Path('Loop/Tests/RealismTests.swift')
s=p.read_text();position=s.rfind('\n}')
assert position > 0
s=s[:position]+'''
    func testAllWeatherModesRenderPortraitFrames() throws {
        let bounds=CGRect(x:0,y:0,width:128,height:224)
        let image=CIImage(color:CIColor(red:0.12,green:0.2,blue:0.25)).cropped(to:bounds)
        var tuning=AtmosphereTuning();tuning.placement="front";tuning.density=0.8
        for id in RealismAtmosphere.modes {
            let result=try RealismAtmosphere.apply(image,id:id,time:3.7,mask:nil,amount:0.7,tuning:tuning)
            XCTAssertEqual(result.extent,bounds,id)
            XCTAssertGreaterThan(color(result,x:64,y:112)[3],250,id)
            XCTAssertGreaterThan(color(result,x:2,y:2)[3],250,id)
        }
    }
    func testZeroStrengthDoesNotAlterSourceOrRequireDetection() throws {
        let image=CIImage(color:CIColor(red:0.3,green:0.5,blue:0.7)).cropped(to:extent)
        var settings=EffectSettings();settings.select("ageOlder",category:.face)
        settings.setAmount(0,category:.face)
        let result=try RealismCompositor.apply(image,settings:settings,time:0,preview:false,analysis:EffectsAnalysis(),session:nil)
        XCTAssertEqual(color(result),color(image))
        XCTAssertEqual(result.extent,extent)
    }
'''+s[position:]
p.write_text(s)
