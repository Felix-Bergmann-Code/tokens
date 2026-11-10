// Renders Resources/AppIcon.icns. Run via scripts/build.sh when the icon is missing.
import AppKit

let out = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1),
                        NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)])!.draw(in: path, angle: -90)
    // Two overlapping glows: Claude clay and Codex blue.
    for (color, dx) in [(NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 0.95), -0.09),
                        (NSColor(red: 0.36, green: 0.56, blue: 0.98, alpha: 0.85), 0.09)] {
        let r = rect.width * 0.26
        let c = NSPoint(x: rect.midX + rect.width * dx, y: rect.midY)
        NSGraphicsContext.current?.compositingOperation = .screen
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSColor.white.withAlphaComponent(0.18).setStroke()
    path.lineWidth = max(1, s * 0.006)
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let data = render(px)
    if px <= 512 { try data.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png")) }
    if px >= 32 { try data.write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png")) }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try p.run()
p.waitUntilExit()
