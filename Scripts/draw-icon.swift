import AppKit

// Mindo app icon — a clean knowledge/mind-map glyph (central node branching to
// child nodes, with one second-level branch to suggest a growing map) in white
// on a modern indigo→violet squircle. Renders a 1024×1024 PNG for make-icon.sh.

let S = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background with a diagonal gradient.
let inset: CGFloat = 96
let rect = CGRect(x: inset, y: inset, width: CGFloat(S) - 2 * inset, height: CGFloat(S) - 2 * inset)
let radius = rect.width * 0.2237
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.36, green: 0.42, blue: 1.00, alpha: 1),   // indigo (top-left)
    CGColor(red: 0.58, green: 0.24, blue: 1.00, alpha: 1),   // violet (bottom-right)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
ctx.restoreGState()

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let soft = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)

// Nodes (CG origin is bottom-left; "top" node has the larger y).
let center = CGPoint(x: 512, y: 512)
let top    = CGPoint(x: 512, y: 726)
let left   = CGPoint(x: 348, y: 360)
let right  = CGPoint(x: 676, y: 360)
let leaf   = CGPoint(x: 690, y: 200)   // second-level child of `right`

// Connectors (under the nodes) — gently curved for an organic feel.
func connect(_ a: CGPoint, _ b: CGPoint, width: CGFloat) {
    let mid = CGPoint(x: (a.x + b.x) / 2 + (b.y - a.y) * 0.10,
                      y: (a.y + b.y) / 2 - (b.x - a.x) * 0.10)
    ctx.move(to: a)
    ctx.addQuadCurve(to: b, control: mid)
}
ctx.setStrokeColor(soft)
ctx.setLineWidth(22)
ctx.setLineCap(.round)
connect(center, top, width: 22)
connect(center, left, width: 22)
connect(center, right, width: 22)
connect(right, leaf, width: 22)
ctx.strokePath()

// Nodes (on top of the connectors).
func dot(_ p: CGPoint, _ r: CGFloat) {
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}
dot(center, 82)
dot(top, 50)
dot(left, 50)
dot(right, 50)
dot(leaf, 30)

NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: "/tmp/mindo-icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
