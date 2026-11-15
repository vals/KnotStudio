// Draws the Knot Studio application icon as a 1024×1024 PNG.
// Usage: swift Tools/Icon.swift <output.png>   (Scripts/icon.sh turns it into Resources/AppIcon.icns)
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
// App palette: stage background, default fabric base and accent, collar.
let stageTop = rgb(0.13, 0.16, 0.20), stageBottom = rgb(0.055, 0.07, 0.09)
let navy = rgb(0.08, 0.18, 0.28), gold = rgb(0.88, 0.63, 0.28)
let collar = rgb(0.93, 0.94, 0.95), collarShade = rgb(0.74, 0.76, 0.80)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func path(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: points)
    p.closeSubpath()
    return p
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// Rounded-square plate in the macOS icon grid (824 pt body, 100 pt margin).
let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let plate = CGPath(roundedRect: plateRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(plate); ctx.setFillColor(stageBottom); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(plate); ctx.clip()
ctx.drawLinearGradient(gradient([stageTop, stageBottom], [0, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Soft spotlight behind the knot.
ctx.drawRadialGradient(gradient([rgb(0.35, 0.42, 0.52, 0.45), rgb(0.35, 0.42, 0.52, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 380), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 380), endRadius: 430, options: [])

// Diagonal stripes clipped to a shape, with a side-to-side shading pass for roundness.
func fillStriped(_ shape: CGPath, angle: CGFloat, period: CGFloat, width: CGFloat, phase: CGFloat, base: CGColor) {
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.setFillColor(base); ctx.fill(plateRect)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512); ctx.rotate(by: angle)
    ctx.setFillColor(gold)
    var x = -900 + phase
    while x < 900 { ctx.fill(CGRect(x: x, y: -900, width: width, height: 1800)); x += period }
    ctx.restoreGState()
    let box = shape.boundingBox
    ctx.drawLinearGradient(gradient([rgb(0, 0, 0, 0.42), rgb(1, 1, 1, 0.10), rgb(0, 0, 0, 0.05), rgb(0, 0, 0, 0.45)],
                                    [0, 0.38, 0.62, 1]),
                           start: CGPoint(x: box.minX, y: 0), end: CGPoint(x: box.maxX, y: 0), options: [])
    ctx.restoreGState()
}

// Collar band: the inside of the neckband, seen behind the knot.
let band = CGMutablePath()
band.move(to: CGPoint(x: 330, y: 150))
band.addQuadCurve(to: CGPoint(x: 694, y: 150), control: CGPoint(x: 512, y: 236))
band.addLine(to: CGPoint(x: 660, y: 196))
band.addQuadCurve(to: CGPoint(x: 364, y: 196), control: CGPoint(x: 512, y: 296))
band.closeSubpath()
ctx.saveGState()
ctx.addPath(band); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.62, 0.65, 0.70), rgb(0.80, 0.82, 0.86)], [0, 1]),
                       start: CGPoint(x: 512, y: 190), end: CGPoint(x: 512, y: 250), options: [])
ctx.restoreGState()

// Blade: hangs from under the knot, widens, ends in a point.
let blade = CGMutablePath()
blade.move(to: CGPoint(x: 478, y: 392))
blade.addLine(to: CGPoint(x: 546, y: 392))
blade.addCurve(to: CGPoint(x: 618, y: 770), control1: CGPoint(x: 572, y: 520), control2: CGPoint(x: 606, y: 680))
blade.addLine(to: CGPoint(x: 512, y: 872))
blade.addLine(to: CGPoint(x: 406, y: 770))
blade.addCurve(to: CGPoint(x: 478, y: 392), control1: CGPoint(x: 418, y: 680), control2: CGPoint(x: 452, y: 520))
blade.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0, 0, 0, 0.5))
ctx.addPath(blade); ctx.setFillColor(navy); ctx.fillPath()
ctx.restoreGState()
fillStriped(blade, angle: .pi / 4, period: 64, width: 15, phase: 0, base: navy)
// Dimple under the knot.
ctx.saveGState()
ctx.addPath(blade); ctx.clip()
ctx.addPath(path([CGPoint(x: 503, y: 392), CGPoint(x: 521, y: 392), CGPoint(x: 514, y: 500), CGPoint(x: 510, y: 500)]))
ctx.setFillColor(rgb(0, 0, 0, 0.45)); ctx.fillPath()
ctx.drawLinearGradient(gradient([rgb(0, 0, 0, 0.55), rgb(0, 0, 0, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 392), end: CGPoint(x: 512, y: 450), options: [])
ctx.restoreGState()

// Knot: a rounded inverted trapezoid, stripes running the other way (the cloth is wrapped across).
let knot = CGMutablePath()
knot.move(to: CGPoint(x: 432, y: 262))
knot.addQuadCurve(to: CGPoint(x: 592, y: 262), control: CGPoint(x: 512, y: 246))
knot.addQuadCurve(to: CGPoint(x: 552, y: 404), control: CGPoint(x: 590, y: 340))
knot.addQuadCurve(to: CGPoint(x: 472, y: 404), control: CGPoint(x: 512, y: 416))
knot.addQuadCurve(to: CGPoint(x: 432, y: 262), control: CGPoint(x: 434, y: 340))
knot.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 16, color: rgb(0, 0, 0, 0.55))
ctx.addPath(knot); ctx.setFillColor(navy); ctx.fillPath()
ctx.restoreGState()
fillStriped(knot, angle: -.pi / 4, period: 52, width: 13, phase: 20, base: navy)
// Top highlight on the knot.
ctx.saveGState()
ctx.addPath(knot); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 255), end: CGPoint(x: 512, y: 330), options: [])
ctx.restoreGState()

// Collar wings sit over the knot's top corners.
func wing(_ points: [CGPoint], shadeTo: CGPoint) {
    let shape = path(points)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(shape); ctx.setFillColor(collar); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([collar, collarShade], [0, 1]),
                           start: points[0], end: shadeTo, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}
wing([CGPoint(x: 300, y: 160), CGPoint(x: 470, y: 228), CGPoint(x: 458, y: 318), CGPoint(x: 352, y: 400)],
     shadeTo: CGPoint(x: 420, y: 380))
wing([CGPoint(x: 724, y: 160), CGPoint(x: 554, y: 228), CGPoint(x: 566, y: 318), CGPoint(x: 672, y: 400)],
     shadeTo: CGPoint(x: 604, y: 380))
ctx.restoreGState()

// Thin inner rim so the plate reads on dark backgrounds too.
ctx.addPath(CGPath(roundedRect: plateRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(1, 1, 1, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
