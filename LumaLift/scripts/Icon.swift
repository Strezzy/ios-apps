import AppKit
let destination = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [color(0.49, 0.29, 0.90), color(0.76, 0.48, 0.94), color(1, 0.67, 0.80)])!.draw(in: bounds, angle: 120)
NSGradient(starting: color(1, 0.91, 0.96, 0.75), ending: color(1, 0.8, 0.9, 0))!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: -220, y: 460, width: 1100, height: 1000)), relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
let back = NSBezierPath(roundedRect: NSRect(x: 181, y: 211, width: 652, height: 604), xRadius: 164, yRadius: 164)
let shadow = NSShadow(); shadow.shadowColor = color(0.33, 0.13, 0.65, 0.38); shadow.shadowBlurRadius = 58; shadow.shadowOffset = NSSize(width: 0, height: -28)
NSGraphicsContext.saveGraphicsState(); shadow.set()
color(0.89, 0.76, 1, 0.38).setFill(); back.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(1, 1, 1, 0.60), color(0.83, 0.66, 1, 0.12)])!.draw(in: back, angle: 95)
color(1, 1, 1, 0.66).setStroke(); back.lineWidth = 3; back.stroke()
let inner = NSBezierPath(roundedRect: NSRect(x: 226, y: 248, width: 561, height: 520), xRadius: 131, yRadius: 131)
color(0.55, 0.32, 0.88, 0.12).setFill(); inner.fill()
let play = NSBezierPath()
play.move(to: NSPoint(x: 402, y: 326))
play.curve(to: NSPoint(x: 366, y: 350), controlPoint1: NSPoint(x: 380, y: 312), controlPoint2: NSPoint(x: 366, y: 326))
play.line(to: NSPoint(x: 366, y: 668))
play.curve(to: NSPoint(x: 403, y: 692), controlPoint1: NSPoint(x: 366, y: 694), controlPoint2: NSPoint(x: 381, y: 706))
play.line(to: NSPoint(x: 666, y: 540))
play.curve(to: NSPoint(x: 666, y: 480), controlPoint1: NSPoint(x: 703, y: 520), controlPoint2: NSPoint(x: 701, y: 499))
play.close()
NSGraphicsContext.saveGraphicsState()
let ps = NSShadow(); ps.shadowColor = color(0.38, 0.15, 0.68, 0.40); ps.shadowBlurRadius = 24; ps.shadowOffset = NSSize(width: 0, height: -12); ps.set()
color(0.97, 0.89, 1).setFill(); play.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [color(0.86, 0.71, 1), .white, color(1, 0.91, 0.97)])!.draw(in: play, angle: 105)
color(1, 1, 1, 0.90).setStroke(); play.lineWidth = 3; play.stroke()
func sparkle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: x, y: y + radius))
    p.curve(to: NSPoint(x: x + radius, y: y), controlPoint1: NSPoint(x: x + radius * 0.12, y: y + radius * 0.22), controlPoint2: NSPoint(x: x + radius * 0.22, y: y + radius * 0.12))
    p.curve(to: NSPoint(x: x, y: y - radius), controlPoint1: NSPoint(x: x + radius * 0.22, y: y - radius * 0.12), controlPoint2: NSPoint(x: x + radius * 0.12, y: y - radius * 0.22))
    p.curve(to: NSPoint(x: x - radius, y: y), controlPoint1: NSPoint(x: x - radius * 0.12, y: y - radius * 0.22), controlPoint2: NSPoint(x: x - radius * 0.22, y: y - radius * 0.12))
    p.curve(to: NSPoint(x: x, y: y + radius), controlPoint1: NSPoint(x: x - radius * 0.22, y: y + radius * 0.12), controlPoint2: NSPoint(x: x - radius * 0.12, y: y + radius * 0.22))
    NSGradient(starting: color(1, 0.80, 0.83), ending: color(1, 1, 0.96))!.draw(in: p, angle: 85)
    color(1, 1, 1, 0.8).setStroke(); p.lineWidth = 2; p.stroke()
}
sparkle(770, 784, 118)
sparkle(233, 284, 43)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
