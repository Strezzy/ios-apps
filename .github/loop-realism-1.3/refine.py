from pathlib import Path
p=Path('Loop/Core/RealismKernels.metal')
s=p.read_text()
s=s.replace('float total=0,weight=0;','float total=0,weight=0,lo=1,hi=0;')
s=s.replace('        total+=mask.sample(mask.transform(p+d)).r*w;weight+=w;','        float value=mask.sample(mask.transform(p+d)).r;\n        total+=value*w;weight+=w;lo=min(lo,value);hi=max(hi,value);')
s=s.replace('    float a=clamp(total/max(weight,.0001)+edge*.14,0.0,1.0);','    float a=clamp(total/max(weight,.0001),0.0,1.0);\n    a=mix(a,edge>=0?hi:lo,clamp(abs(edge),0.0,1.0));')
start=s.index('    const int count=112;')
end=s.index('        float a=0;float3 col=',start)
s=s[:start]+'''    // Visit neighboring particles rather than every particle in the frame.
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
        float rad=(.002+.004*hash21(cell+29.0))*depth*(.5+size);
        float2 center=(cell+float2(.15+.7*hx+sin(t*.35+fi)*.10,.15+.7*hy))*cellSize+flow*t;
        float2 d=p-center;
'''+s[end:]
p.write_text(s)
p=Path('Loop/Tests/RealismTests.swift');s=p.read_text()
s=s.replace('        XCTAssertFalse(analysis.geometry.isEmpty,"The real portrait must produce usable landmarks.")','''        XCTAssertFalse(analysis.geometry.isEmpty,"The real portrait must produce usable landmarks.")
        let alpha=try XCTUnwrap(analysis.personMask)
        XCTAssertLessThan(color(alpha,x:500,y:500)[0],100,"Background must not become opaque foreground.")
        XCTAssertGreaterThan(color(alpha,x:256,y:256)[0],150,"The visible torso must remain foreground.")''')
pos=s.rfind('\n}')
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
'''+s[pos:];p.write_text(s)
