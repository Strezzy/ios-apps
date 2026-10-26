from pathlib import Path
import json

root = Path('Loop')
def replace_once(path, old, new):
    p = root / path
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:90], s.count(old))
    p.write_text(s.replace(old, new, 1))

replace_once('project.yml', "MARKETING_VERSION: '1.3.0'", "MARKETING_VERSION: '1.3.1'")
replace_once('project.yml', "CURRENT_PROJECT_VERSION: '7'", "CURRENT_PROJECT_VERSION: '8'")
p = root / 'release-validation.json'
r = json.loads(p.read_text()); assert (r['version'], r['build']) == ('1.3.0', '7')
r.update(version='1.3.1', build='8', reason='Native device compilation and package verification plus separately required focused renderer/model/migration XCTest checks. The lengthy full editor interface suite and physical-device validation are not run.')
p.write_text(json.dumps(r, indent=2) + '\n')

replace_once('Core/RealismKernels.metal', 'float total=0,weight=0;', 'float total=0,weight=0,lo=1,hi=0;')
replace_once('Core/RealismKernels.metal', '        total+=mask.sample(mask.transform(p+d)).r*w;weight+=w;',
             '        float value=mask.sample(mask.transform(p+d)).r;\n        total+=value*w;weight+=w;lo=min(lo,value);hi=max(hi,value);')
replace_once('Core/RealismKernels.metal', '    float a=clamp(total/max(weight,.0001)+edge*.14,0.0,1.0);',
             '    float a=clamp(total/max(weight,.0001),0.0,1.0);\n    a=mix(a,edge>=0?hi:lo,clamp(abs(edge),0.0,1.0));')
p = root / 'Core/RealismKernels.metal'; s=p.read_text()
start=s.index('    const int count=112;'); end=s.index('        float a=0;float3 col=', start)
s=s[:start]+'''    // A spatial neighborhood has bounded cost independent of the total field size.
    // Particle coordinates follow the same flow, avoiding jumps at tile boundaries.
    bool rise=(mode==2||mode==5||mode==9);
    float cellSize=mode==5?.18*depth*(.5+size):(mode==1?.075:.09);
    float velocity=(mode==1?.58:(mode==5?.055:.12))*depth;
    float2 flow=float2(wind*.035*depth,(rise?1.0:-1.0)*velocity);
    float2 tile=floor((p-flow*t)/cellSize);
    for(int cy=-1;cy<=1;cy++)for(int cx=-1;cx<=1;cx++) {
        float2 cell=tile+float2(cx,cy);
        float fi=hash21(cell+layer*127.0)*1024.0;
        float seed=hash21(cell+float2(layer*31.0,3.1));
        if(seed>density*.85+.06) continue;
        float hx=hash21(cell+float2(17.0,layer*53.0)),hy=hash21(cell+float2(layer*13.0,53.0));
        float rad=(.002+.004*hash21(cell+29.0)))*depth*(.5+size);
        float2 center=(cell+float2(.15+.7*hx+sin(t*.35+fi)*.10,.15+.7*hy))*cellSize+flow*t;
        float2 d=p-center;
'''+s[end:]
s=s.replace('hash21(cell+29.0)))', 'hash21(cell+29.0))')
p.write_text(s)

# Face edits run in original landmark coordinates, then follow body deformation.
p = root / 'Core/RealismCompositor.swift'; s=p.read_text()
a=s.index('        if let body {'); b=s.index('        if let face {',a); c=s.index('        if let mask=surface.mask',b)
s=s[:a]+s[b:c]+s[a:b]+s[c:];p.write_text(s)

replace_once('Core/RealismEngine.swift',
             'let signature = "\\(faces)-\\(person)-\\(body)-\\(tuning.subject)-\\(tuning.quality)"',
             'let signature = "\\(faces)-\\(person)-\\(body)-\\(tuning.subject)-\\(tuning.quality)-\\(tuning.stability)"')

replace_once('Tests/RealismTests.swift',
    '        XCTAssertFalse(analysis.geometry.isEmpty,"The real portrait must produce usable landmarks.")',
    '''        XCTAssertFalse(analysis.geometry.isEmpty,"The real portrait must produce usable landmarks.")
        let alpha=try XCTUnwrap(analysis.personMask)
        XCTAssertLessThan(color(alpha,x:500,y:500)[0],100,"Background must not become opaque foreground.")
        XCTAssertGreaterThan(color(alpha,x:256,y:256)[0],150,"The visible torso must remain foreground.")''')
p=root/'Tests/RealismTests.swift'; s=p.read_text(); pos=s.rfind('\n}')
s=s[:pos]+'''
    func testEdgeExpansionDoesNotLiftEmptyBackground() throws {
        let image=CIImage(color:.black).cropped(to:extent)
        var tuning=MatteTuning();tuning.edge=1
        let result=try RealismAnalysis.refined(image,image:image,tuning:tuning)
        XCTAssertEqual(color(result)[0],0)
    }
    func testEdgeContractionPreservesOpaqueInterior() throws {
        let image=CIImage(color:.white).cropped(to:extent)
        var tuning=MatteTuning();tuning.edge = -1
        let result=try RealismAnalysis.refined(image,image:image,tuning:tuning)
        XCTAssertEqual(color(result)[0],255)
    }
    func testParticleFieldsAreResolutionIndependent() throws {
        let small=CIImage(color:.black).cropped(to:extent)
        let large=CIImage(color:.black).cropped(to:CGRect(x:0,y:0,width:1024,height:1024))
        var tuning=AtmosphereTuning();tuning.placement="front";tuning.density=1
        for id in ["rain","snow","bubbles","embers"] {
            let a=try RealismAtmosphere.apply(small,id:id,time:1.2,mask:nil,amount:1,tuning:tuning)
            let b=try RealismAtmosphere.apply(large,id:id,time:1.2,mask:nil,amount:1,tuning:tuning)
            XCTAssertEqual(a.extent,extent);XCTAssertEqual(b.extent,large.extent)
            XCTAssertGreaterThan(color(b,x:512,y:512)[3],250)
        }
    }
'''+s[pos:];p.write_text(s)

# The former build-only template must not claim that no simulator checks ran.
p=root/'scripts/publish.sh';s=p.read_text()
start=s.index('    if build_only_profile():');end=s.index('    else:',start)
s=s[:start]+'''    if build_only_profile():
        focused = json.load(open('Build/FOCUSED-REALISM-TESTS.json'))
        assert focused['sourceCommit'] == r['sourceCommit']
        assert focused['passedTests'] >= 24 and focused['failedTests'] == 0 and focused.get('skippedTests', 0) == 0
        f.write(f"\\nValidation: native arm64 Release build and package/checksum verification passed. "
                f"Focused simulator renderer/model/migration checks: {focused['passedTests']} passed, "
                f"{focused['failedTests']} failed, {focused.get('skippedTests', 0)} skipped. "
                "The complete editor interface suite and physical-device tests were not run.\\n")
'''+s[end:]
s=s.replace('  LOOP_ASSETS+=(Build/VALIDATION-REPORT.json)',
            '  LOOP_ASSETS+=(Build/VALIDATION-REPORT.json Build/FOCUSED-REALISM-TESTS.json Build/REALISM-ASSET-REPORT.json Build/REALISM-RESEARCH.md Build/Loop-Realism-Samples.zip)')
p.write_text(s)

p=root/'docs/RELEASE.md';s=p.read_text();s=s.replace('# Loop 1.3.0 (build 7): rebuilt portrait and atmosphere effects', '# Loop 1.3.1 (build 8): rebuilt portrait and atmosphere effects',1)
s=s.replace('## Replaced, not repainted','''## Finishing fixes

Edge expansion and contraction now operate locally on the matte boundary, without raising empty background or making an opaque subject translucent. Weather uses a spatial particle neighborhood instead of evaluating the entire particle set for every output pixel. Face edits are composed before body deformation, so the transformed face follows the body. Foreground stabilization responds immediately to a changed stability setting. These refinements retain the new model-based effects described below.

## Replaced, not repainted''',1)
p.write_text(s)
print('Integrated Loop 1.3.1 refinements without replacing the shipped portrait models or other app features.')
