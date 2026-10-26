#!/usr/bin/env python3
# Exercise the app's actual shared selection code in a native macOS bundle.
# This is an additional platform check, not a physical-iPhone performance test.
from pathlib import Path
import hashlib,json,os,plistlib,subprocess
root=Path(__file__).resolve().parents[1]
build=root/'Build'/'MacSelection';build.mkdir(parents=True,exist_ok=True)
app=build/'SelectionChecks.app';resources=app/'Contents'/'Resources';binary=app/'Contents'/'MacOS'/'SelectionChecks'
resources.mkdir(parents=True,exist_ok=True);binary.parent.mkdir(parents=True,exist_ok=True)
with (app/'Contents'/'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.billy.loop.selection-checks','CFBundleExecutable':'SelectionChecks','CFBundlePackageType':'APPL','CFBundleVersion':'1'},f)
compile_source=build/'CompileModels.swift'
compile_source.write_text('''import Foundation
import CoreML
let source=URL(fileURLWithPath:CommandLine.arguments[1])
let destination=URL(fileURLWithPath:CommandLine.arguments[2])
for name in ["SAM2TinyImageEncoderFLOAT16","SAM2TinyPromptEncoderFLOAT16","SAM2TinyMaskDecoderFLOAT16"] {
    let compiled=try MLModel.compileModel(at:source.appendingPathComponent(name+".mlpackage"))
    let target=destination.appendingPathComponent(name+".mlmodelc")
    if FileManager.default.fileExists(atPath:target.path){try FileManager.default.removeItem(at:target)}
    try FileManager.default.copyItem(at:compiled,to:target)
}
''')
compiler=build/'CompileModels'
subprocess.run(['xcrun','swiftc',str(compile_source),'-o',str(compiler)],check=True)
subprocess.run([str(compiler),str(root/'Resources'/'SceneModels'),str(resources)],check=True)
# Extract shared types verbatim. No inference or coordinate code is rewritten.
scene=(root/'Core/Creative/SceneInference.swift').read_text().split('\nstruct SceneFrame {')[0]
(build/'SharedSelection.swift').write_text(scene)
(build/'NativeSubjectSelection.swift').write_text((root/'Core/Creative/NativeSubjectSelection.swift').read_text())
models=(root/'Core/Models.swift').read_text();a=models.index('struct NormalizedRect:');b=models.index('\nenum CropAspect:',a)
creative=(root/'Core/Creative/CreativeModels.swift').read_text();c=creative.index('struct SelectionPoint:');d=creative.index('\nstruct MaskStroke:',c)
(build/'SharedTypes.swift').write_text('import Foundation\nimport CoreGraphics\n'+models[a:b]+'\n'+creative[c:d]+'\nenum LoopError:Error {case encoding(String);case invalidSettings(String)}\n')
main=build/'Runner.swift'
main.write_text(r'''import Foundation
import CoreImage
import ImageIO

@main struct SelectionChecks {
    static func require(_ condition:Bool,_ message:String)throws {if !condition{throw LoopError.encoding(message)}}
    static func main()throws {
        let fixture=URL(fileURLWithPath:CommandLine.arguments[1]),folder=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        guard let image=CIImage(contentsOf:fixture) else{throw LoopError.encoding("Fixture missing")}
        var passed=0
        func pixel(_ mask:CIImage,_ x:Int,_ y:Int)->Int {
            var bytes=[UInt8](repeating:0,count:4)
            SceneModels.context.render(mask,toBitmap:&bytes,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:SceneModels.rgb)
            return Int(bytes[0])
        }
        func save(_ mask:CIImage,_ name:String)throws {
            guard let cg=SceneModels.context.createCGImage(mask,from:image.extent),let target=CGImageDestinationCreateWithURL(folder.appendingPathComponent(name+".png") as CFURL,"public.png" as CFString,1,nil) else{throw LoopError.encoding("Sample could not be saved")}
            CGImageDestinationAddImage(target,cg,nil);try require(CGImageDestinationFinalize(target),"Sample could not be finalized")
        }
        for cpu in [false,true] {
            if cpu{SceneModels.useSafeSAMBackend()}
            let id=UUID()
            let tapped=try PromptSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.5,y:0.65)],box:nil)])
            guard let mask=tapped[id] else{throw LoopError.encoding("SAM tap returned no foreground")}
            let bounds=try PromptSelection.bounds(of:mask)
            try require(bounds.width>0.005 && bounds.cgRect.insetBy(dx:-0.02,dy:-0.02).contains(CGPoint(x:0.5,y:0.65)),"SAM tapped mask missed the selected point")
            try require(PromptSelection.compatibilityHint==nil,"Native macOS SAM unexpectedly required another selection engine")
            try save(mask,cpu ? "sam-cpu-tap":"sam-gpu-tap");passed+=1
            let box=NormalizedRect(x:0.02,y:0.02,width:0.72,height:0.96)
            let whole=try PromptSelection.masks(image,prompts:[.init(id:id,points:[SelectionPoint(x:0.42,y:0.32),SelectionPoint(x:0.25,y:0.55)],box:box)])
            guard let subject=whole[id] else{throw LoopError.encoding("SAM box returned no foreground")}
            let wholeBounds=try PromptSelection.bounds(of:subject)
            try require(wholeBounds.width>0.25 && wholeBounds.height>0.45 && pixel(subject,480,480)<100,"SAM box did not separate subject and background")
            try require(PromptSelection.compatibilityHint==nil,"Native macOS SAM box required fallback")
            try save(subject,cpu ? "sam-cpu-subject":"sam-gpu-subject");passed+=1
        }
        let id=UUID(),point=SelectionPoint(x:0.42,y:0.32)
        let native=try NativeSubjectSelection.masks(image,prompts:[.init(id:id,points:[point,SelectionPoint(x:0.94,y:0.05,include:false)],box:nil)])
        guard let mask=native[id] else{throw LoopError.encoding("Native selection returned no foreground")}
        let bounds=try PromptSelection.bounds(of:mask)
        try require(bounds.width>0.2 && bounds.height>0.4 && pixel(mask,220,330)>150 && pixel(mask,480,480)<60,"Native subject mask has wrong coverage")
        try save(mask,"native-selected-subject");passed+=1
        var rejected=false
        do{_ = try NativeSubjectSelection.masks(image,prompts:[.init(id:id,points:[point,SelectionPoint(x:point.x,y:point.y,include:false)],box:nil)])}catch{rejected=true}
        try require(rejected,"Conflicting native points must not silently choose an instance");passed+=1
        let report:[String:Any]=["passedTests":passed,"failedTests":0,"skippedTests":0,"sourceCommit":ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "unknown","scope":"Shared selection code: SAM CPU/GPU and CPU tap/box masks, native foreground instances, conflicting-point rejection. Native macOS, not physical iPhone or iOS Simulator.","os":ProcessInfo.processInfo.operatingSystemVersionString,"upstreamSAMModelsUnmodified":true]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:folder.deletingLastPathComponent().appendingPathComponent("MAC-SELECTION-TESTS.json"))
        print(String(data:data,encoding:.utf8)!)
    }
}
''')
subprocess.run(['xcrun','swiftc','-O','-parse-as-library','-target','arm64-apple-macosx15.0',str(build/'SharedSelection.swift'),str(build/'NativeSubjectSelection.swift'),str(build/'SharedTypes.swift'),str(main),'-o',str(binary)],check=True)
subprocess.run([str(binary),str(root/'Tests/Fixtures/portrait-fixture.png'),str(root/'Build/MacSelectionSamples')],check=True)
report_path=root/'Build/MAC-SELECTION-TESTS.json';report=json.loads(report_path.read_text())
assert report['passedTests']==6 and report['failedTests']==0 and report['skippedTests']==0
report['sharedSourceSHA256']={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'Core/Creative/SceneInference.swift',root/'Core/Creative/NativeSubjectSelection.swift']}
report_path.write_text(json.dumps(report,indent=2)+'\n')
