import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/brand"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor { NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1) }
func leaf() -> NSBezierPath {
    let p = NSBezierPath(); p.windingRule = .evenOdd
    p.move(to: NSPoint(x: 22, y: 73)); p.curve(to: NSPoint(x: 75, y: 18), controlPoint1: NSPoint(x: 10, y: 53), controlPoint2: NSPoint(x: 24, y: 21))
    p.curve(to: NSPoint(x: 40, y: 79), controlPoint1: NSPoint(x: 87, y: 54), controlPoint2: NSPoint(x: 66, y: 82))
    p.line(to: NSPoint(x: 22, y: 88)); p.close()
    p.move(to: NSPoint(x: 31, y: 66)); p.curve(to: NSPoint(x: 44, y: 48), controlPoint1: NSPoint(x: 38, y: 63), controlPoint2: NSPoint(x: 36, y: 48))
    p.curve(to: NSPoint(x: 53, y: 56), controlPoint1: NSPoint(x: 49, y: 48), controlPoint2: NSPoint(x: 48, y: 56))
    p.curve(to: NSPoint(x: 69, y: 34), controlPoint1: NSPoint(x: 60, y: 56), controlPoint2: NSPoint(x: 61, y: 40))
    p.curve(to: NSPoint(x: 57, y: 64), controlPoint1: NSPoint(x: 67, y: 46), controlPoint2: NSPoint(x: 65, y: 63))
    p.curve(to: NSPoint(x: 43, y: 57), controlPoint1: NSPoint(x: 48, y: 67), controlPoint2: NSPoint(x: 47, y: 56))
    p.curve(to: NSPoint(x: 31, y: 66), controlPoint1: NSPoint(x: 40, y: 57), controlPoint2: NSPoint(x: 38, y: 68)); p.close()
    return p
}
func render(_ name: String, size: Int, dark: Bool, icon: Bool) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: CGFloat(size)); transform.scaleX(by: CGFloat(size) / 1024, yBy: -CGFloat(size) / 1024); transform.concat()
    if icon {
        color(dark ? 0x14241D : 0xE6F0E9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202).fill()
    }
    let glyph = leaf(); let scale = AffineTransform(scale: 9)
    glyph.transform(using: scale); glyph.transform(using: AffineTransform(translationByX: 64, byY: 18))
    color(dark ? 0xA6D7B8 : 0x2D5E46).setFill(); glyph.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
try render("utterleaf-app-icon.png", size: 1024, dark: true, icon: true)
try render("utterleaf-app-icon-light.png", size: 1024, dark: false, icon: true)
try render("utterleaf-mark-dark.png", size: 512, dark: true, icon: false)
try render("utterleaf-mark-light.png", size: 512, dark: false, icon: false)
print("Rendered UtterLeaf brand assets.")
