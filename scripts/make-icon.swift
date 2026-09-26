// Renders the 1024×1024 app icon. Run: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Wall
NSGradient(colors: [color(0x3A271B), color(0x1E140E), color(0x110B08)])!
    .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
NSGradient(colors: [color(0xFFB36B, 0.35), color(0xFFB36B, 0)])!
    .draw(fromCenter: NSPoint(x: size / 2, y: size * 1.02), radius: 0,
          toCenter: NSPoint(x: size / 2, y: size * 1.02), radius: size * 0.75, options: [])

let shelfTop: CGFloat = 250

// Books: (x, width, height, top colour, bottom colour, band colour, lean degrees)
let books: [(CGFloat, CGFloat, CGFloat, UInt32, UInt32, UInt32, CGFloat)] = [
    (205, 150, 520, 0xF0B266, 0xC7843A, 0x7A4A1E, 0),
    (370, 130, 460, 0xEFE3C8, 0xCBBE9F, 0x8E7E5C, 0),
    (515, 165, 560, 0x2F6F6B, 0x1B4644, 0xE9D9B6, 0),
    (795, 125, 490, 0xB3262E, 0x7A151B, 0xF0D7A8, 14),
]

for (x, w, h, top, bottom, band, lean) in books {
    ctx.saveGState()
    if lean != 0 {
        ctx.translateBy(x: x, y: shelfTop)
        ctx.rotate(by: lean * .pi / 180)
        ctx.translateBy(x: -x, y: -shelfTop)
    }
    let rect = NSRect(x: x, y: shelfTop, width: w, height: h)
    ctx.setShadow(offset: CGSize(width: 10, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    color(top).setFill()
    path.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    NSGradient(colors: [color(top), color(bottom)])!.draw(in: path, angle: 0)
    // Spine highlight + bands
    NSGradient(colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: x + 12, y: shelfTop, width: w * 0.3, height: h), angle: 0)
    color(band, 0.9).setFill()
    NSBezierPath(rect: NSRect(x: x, y: shelfTop + h - 90, width: w, height: 16)).fill()
    NSBezierPath(rect: NSRect(x: x, y: shelfTop + 70, width: w, height: 16)).fill()
    NSBezierPath(roundedRect: NSRect(x: x + w * 0.3, y: shelfTop + h * 0.45, width: w * 0.4, height: 70),
                 xRadius: 6, yRadius: 6).fill()
    ctx.restoreGState()
}

// Shelf plank
let plank = NSRect(x: 90, y: shelfTop - 70, width: size - 180, height: 70)
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: NSColor.black.withAlphaComponent(0.7).cgColor)
color(0x6E4122).setFill()
NSBezierPath(roundedRect: plank, xRadius: 8, yRadius: 8).fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
NSGradient(colors: [color(0xA8703F), color(0x6E4122), color(0x3F2413)])!
    .draw(in: NSBezierPath(roundedRect: plank, xRadius: 8, yRadius: 8), angle: -90)
color(0xFFFFFF, 0.25).setFill()
NSBezierPath(rect: NSRect(x: plank.minX + 8, y: plank.maxY - 26, width: plank.width - 16, height: 3)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
