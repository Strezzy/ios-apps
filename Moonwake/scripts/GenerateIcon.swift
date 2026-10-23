import Foundation
import AppKit
import CoreGraphics

// This build-time drawing is authored in native Swift. It has no external asset or
// network dependency and produces a fully opaque App Store-sized icon.
let dimension = 128
guard let context = CGContext(data: nil, width: dimension, height: dimension,
                              bitsPerComponent: 8, bytesPerRow: dimension * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot allocate icon drawing surface")
}
context.translateBy(x: 0, y: CGFloat(dimension)); context.scaleBy(x: 1, y: -1)
context.setShouldAntialias(false); context.interpolationQuality = .none

func fill(_ color: UInt32, _ alpha: CGFloat = 1) {
    context.setFillColor(CGColor(red: CGFloat((color >> 16) & 255)/255,
                                green: CGFloat((color >> 8) & 255)/255,
                                blue: CGFloat(color & 255)/255, alpha: alpha))
}
func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32, _ alpha: CGFloat = 1) {
    fill(color, alpha); context.fill(CGRect(x: x, y: y, width: w, height: h))
}
func polygon(_ points: [(Int, Int)], _ color: UInt32, _ alpha: CGFloat = 1) {
    guard let first = points.first else { return }
    fill(color, alpha); context.beginPath(); context.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { context.addLine(to: CGPoint(x: point.0, y: point.1)) }
    context.closePath(); context.fillPath()
}
func ellipse(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32, _ alpha: CGFloat = 1) {
    let rx = Double(w)/2, ry = Double(h)/2
    for row in 0..<h {
        let n = (Double(row)+0.5-ry)/ry
        let half = Int((rx*sqrt(max(0,1-n*n))).rounded())
        rect(x+w/2-half,y+row,half*2,1,color,alpha)
    }
}

rect(0,0,128,128,0x0B1534)
for y in 0..<77 { rect(0,y,128,1,0x273D60,CGFloat(y)/110) }
for star in [(14,14),(31,27),(57,12),(74,20),(111,13),(119,40),(8,39),(25,52)] {
    rect(star.0,star.1,1,1,0xBDDBD8,0.85)
}
rect(55,9,3,1,0xDBEADF,0.6); rect(56,8,1,3,0xDBEADF,0.6)
ellipse(83,13,25,25,0xC6E5CF)
ellipse(77,10,24,25,0x192A48)
polygon([(0,53),(9,43),(17,43),(17,36),(24,34),(33,41),(40,42),(47,52),(51,54)],0x30445F)
polygon([(73,54),(84,47),(88,42),(94,42),(99,36),(109,38),(113,46),(121,47),(128,52),(128,58)],0x344B67)
rect(0,56,128,42,0x1C4262)
rect(0,56,128,2,0x56839A)
for y in stride(from: 61, to: 96, by: 5) {
    rect(80-(y-60)/2,y,17+(y-60)/2,1,0x81ABAF,0.6)
    rect((y*13)%61,y+2,8+(y%7),1,0x386B89)
}
polygon([(0,100),(12,97),(12,93),(25,90),(34,91),(39,87),(53,87),(63,85),(72,88),(83,88),(89,91),(106,92),(116,95),(128,95),(128,128),(0,128)],0x354F50)
polygon([(0,107),(12,104),(25,105),(25,101),(40,99),(54,99),(73,100),(85,97),(97,101),(112,101),(128,104),(128,128),(0,128)],0x3E6256)
for i in 0..<37 {
    let x = (i*31+7)%126, y = 105+(i*7)%21
    rect(x,y,1,3,0x749278); rect(x+2,y-1,1,3,0x5F8668)
}
// Hero: broad, readable white hair and crimson scarf establish the game identity.
ellipse(42,118,50,6,0x142D38,0.8)
polygon([(49,96),(63,96),(59,119),(41,119),(41,114),(50,110)],0x0B1B32)
polygon([(64,96),(79,96),(82,113),(90,115),(90,120),(73,120),(67,109)],0x0B1B32)
rect(52,99,4,12,0x29465C); rect(73,100,4,12,0x29465C)
rect(49,77,29,24,0x143544); rect(53,78,20,17,0x28566A)
rect(49,96,31,6,0x102C40); rect(62,96,5,3,0xC6B484)
rect(76,78,10,11,0xD5AA94); rect(77,78,8,5,0xF4CAB0)
polygon([(49,75),(39,74),(33,68),(24,70),(20,77),(29,77),(36,83),(45,82),(51,83)],0xB13C55)
rect(25,70,9,4,0xDE5D6C); rect(36,76,13,4,0xDB5A68)
rect(48,73,31,9,0xB93B55); rect(49,72,28,4,0xF1767F)
rect(52,53,27,21,0xC28B88); rect(58,54,23,20,0xEEC5AA)
rect(58,59,4,9,0x2B2535); rect(73,59,4,9,0x2B2535)
rect(65,70,5,2,0xB5817D)
polygon([(39,45),(45,45),(45,38),(54,38),(54,33),(64,33),(64,27),(68,27),(68,34),(77,34),(77,39),(84,39),(84,54),(80,54),(80,59),(74,59),(74,54),(68,54),(68,62),(62,62),(62,57),(56,57),(56,64),(50,64),(50,58),(45,58),(45,54),(39,54)],0xCADFE3)
polygon([(41,45),(48,45),(48,40),(55,40),(55,35),(66,35),(66,32),(68,35),(76,36),(76,41),(82,41),(82,51),(75,51),(75,54),(68,54),(68,57),(62,57),(62,53),(57,53),(57,58),(50,58),(50,53),(41,53)],0xF2FFF3)
rect(46,53,4,7,0xA8BED0); rect(55,55,4,7,0xBCD3DE)
// The spectral greatsword crosses the foreground, with stepped cyan bloom.
polygon([(27,103),(91,66),(97,58),(104,60),(105,68),(112,69),(106,77),(44,112),(34,112)],0x48B7B6,0.35)
polygon([(30,103),(92,69),(98,60),(102,63),(102,71),(109,72),(104,76),(42,109),(35,110)],0x92F6DD)
polygon([(34,103),(94,70),(98,64),(99,72),(105,73),(101,75),(41,107),(36,108)],0xF1FFF1)
polygon([(26,100),(29,97),(42,111),(39,115)],0x9ED6C5)
polygon([(22,109),(29,103),(33,107),(26,113)],0xCAB987)
rect(21,109,5,5,0x769E9B)
// Amber companion and a hint of the little moss guardian.
ellipse(10,76,18,18,0xEBA33C,0.25); ellipse(12,78,14,14,0xF6C76E)
ellipse(14,80,10,10,0xEAA139); rect(15,80,3,2,0xFFF2BD)
rect(17,85,1,3,0xA96431); rect(22,85,1,3,0xA96431)
rect(103,103,17,14,0xBB944D); rect(105,98,13,10,0xD5AC53)
rect(107,101,10,5,0x223C3D); rect(108,102,2,3,0xE5CA6B); rect(114,102,2,3,0xE5CA6B)
rect(108,94,8,5,0x6A9150); rect(110,91,4,5,0x89A15E)
rect(104,116,4,6,0x936B3A); rect(115,116,4,6,0x936B3A)

guard let smallImage = context.makeImage(),
      let output = CGContext(data:nil, width:1024, height:1024, bitsPerComponent:8,
                             bytesPerRow:4096, space:CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot render icon")
}
output.interpolationQuality = .none
output.draw(smallImage,in:CGRect(x:0,y:0,width:1024,height:1024))
guard let image = output.makeImage(),
      let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {
    fatalError("Cannot encode icon PNG")
}
let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let url = URL(fileURLWithPath:destination)
try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
try png.write(to:url,options:.atomic)
print("Generated opaque 1024×1024 Moonwake icon at \(destination)")
