import AppKit
import CoreGraphics

// Renders the SiteSearch app icon master at 1024x1024.
// Full-bleed square art; macOS applies its own tile mask.

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let s = CGFloat(size)

// Background: deep slate-blue diagonal gradient.
let colors = [
    CGColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 1),
    CGColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1),
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Subtle radial glow behind the lens so the glyph sits in light.
let glow = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.35),
    CGColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.46, y: s * 0.58), startRadius: 0,
                       endCenter: CGPoint(x: s * 0.46, y: s * 0.58), endRadius: s * 0.5, options: [])

// Magnifying glass: ring + handle, white, generous stroke.
let stroke = s * 0.075
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
ctx.setLineWidth(stroke)
ctx.setLineCap(.round)

let lensCenter = CGPoint(x: s * 0.46, y: s * 0.58)
let lensRadius = s * 0.21
ctx.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                             width: lensRadius * 2, height: lensRadius * 2))

// Handle from the lens rim toward the lower right.
let angle = CGFloat(-45.0 * .pi / 180.0)
let from = CGPoint(x: lensCenter.x + cos(angle) * (lensRadius + stroke * 0.45),
                   y: lensCenter.y + sin(angle) * (lensRadius + stroke * 0.45))
let to = CGPoint(x: lensCenter.x + cos(angle) * (lensRadius + s * 0.20),
                 y: lensCenter.y + sin(angle) * (lensRadius + s * 0.20))
ctx.move(to: from)
ctx.addLine(to: to)
ctx.strokePath()

// Inside the lens: a stylized "site" - three latitude lines of a globe,
// clipped to the lens, hinting at "websites" without lettering.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius + stroke * 0.7,
                          y: lensCenter.y - lensRadius + stroke * 0.7,
                          width: (lensRadius - stroke * 0.7) * 2,
                          height: (lensRadius - stroke * 0.7) * 2))
ctx.clip()
ctx.setLineWidth(stroke * 0.42)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
for dy in [-0.4, 0.0, 0.4] {
    let y = lensCenter.y + lensRadius * CGFloat(dy)
    ctx.move(to: CGPoint(x: lensCenter.x - lensRadius, y: y))
    ctx.addLine(to: CGPoint(x: lensCenter.x + lensRadius, y: y))
}
ctx.strokePath()
// One meridian.
ctx.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius * 0.45, y: lensCenter.y - lensRadius,
                             width: lensRadius * 0.9, height: lensRadius * 2))
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
