from pathlib import Path
p=Path('Loop/Core/Creative/CreativeAssets.swift')
s=p.read_text()
old='        let prepared=try RealismKernels.color("loopLUTDomain",extent:image.extent,arguments:[image,CIVector(values:lut.domainMin.map(CGFloat.init),count:3),CIVector(values:lut.domainMax.map(CGFloat.init),count:3)])'
new='''        let low = CIVector(x: CGFloat(lut.domainMin[0]), y: CGFloat(lut.domainMin[1]), z: CGFloat(lut.domainMin[2]))
        let high = CIVector(x: CGFloat(lut.domainMax[0]), y: CGFloat(lut.domainMax[1]), z: CGFloat(lut.domainMax[2]))
        let prepared = try RealismKernels.color("loopLUTDomain", extent: image.extent, arguments: [image, low, high])'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
