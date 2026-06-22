import AppKit

// kep app icon — "keep your ideas". A bold lowercase "k" wordmark with a small
// node/idea dot, white on the teal brand gradient squircle. Renders a 1024×1024
// PNG for make-icon.sh.

let S = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background with a diagonal teal gradient (matches Color.kepAccent).
let inset: CGFloat = 96
let rect = CGRect(x: inset, y: inset, width: CGFloat(S) - 2 * inset, height: CGFloat(S) - 2 * inset)
let radius = rect.width * 0.2237
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(red: 0.16, green: 0.80, blue: 0.72, alpha: 1),   // light teal (top-left)
    CGColor(red: 0.05, green: 0.55, blue: 0.50, alpha: 1),   // deep teal (bottom-right)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

// Bold lowercase "k", white, centred (nudged left to leave room for the dot).
let k = "k" as NSString
let font = NSFont.systemFont(ofSize: 640, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let kSize = k.size(withAttributes: attrs)
k.draw(at: CGPoint(x: 512 - kSize.width / 2 - 36, y: 512 - kSize.height / 2),
       withAttributes: attrs)

// A small "idea" node dot at the upper right — the kept thought.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let dotR: CGFloat = 60
ctx.fillEllipse(in: CGRect(x: 690 - dotR, y: 700 - dotR, width: dotR * 2, height: dotR * 2))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/kep-icon-1024.png"))
print("wrote /tmp/kep-icon-1024.png")
