import AppKit
import SceneKit

enum FabricPattern: String, CaseIterable, Identifiable {
    case stripes = "Regimental", dots = "Pin dots", check = "Windowpane", solid = "Solid"
    case imported = "Imported image"
    var id: String { rawValue }
}

/// What the cloth is drawn with. Fabric shows the chosen swatch; the other two
/// are diagnostics that leave the swatch settings untouched.
enum FabricDisplay: String, CaseIterable, Identifiable {
    case fabric = "Fabric", grid = "Grid", faces = "Faces"
    var id: String { rawValue }
}

/// The kind of cloth: how thick it is (which sets the bulk of the knot), how
/// coarse its weave looks and how much it shines.
enum ClothKind: String, CaseIterable, Identifiable {
    case fineSilk = "Fine silk", twill = "Silk twill", wool = "Wool"
    var id: String { rawValue }
    /// Thickness relative to an ordinary silk twill.
    var weight: Double { self == .fineSilk ? 0.75 : (self == .twill ? 1.0 : 1.45) }
    var roughness: Double { self == .fineSilk ? 0.50 : (self == .twill ? 0.66 : 0.95) }
    /// Size of one weave tile on the cloth, cm, and the depth of its relief.
    var weaveTile: Double { self == .fineSilk ? 0.30 : (self == .twill ? 0.45 : 0.7) }
    var weaveDepth: Double { self == .fineSilk ? 0.45 : (self == .twill ? 0.8 : 0.85) }
}

struct FabricSettings: Equatable {
    var pattern: FabricPattern = .stripes
    var cloth: ClothKind = .twill
    var display: FabricDisplay = .fabric
    var base = NSColor(srgbRed: 0.08, green: 0.18, blue: 0.28, alpha: 1)
    var accent = NSColor(srgbRed: 0.88, green: 0.63, blue: 0.28, alpha: 1)
    /// Width of one pattern repeat on the flat cloth, cm.
    var repeatCM = 3.6
    var offsetCM = 0.0
    /// Degrees, counter-clockwise on the flat front.
    var angle = 32.0
    var image: NSImage?

    var aspect: Double {
        guard display == .fabric, pattern == .imported, let image else { return 1 }
        let size = FabricImage.pixelSize(image)
        return Double(size.height / max(1, size.width))
    }

    /// Everything that changes the texture pixels (not its placement).
    var textureKey: String {
        func hex(_ c: NSColor) -> String {
            let d = c.usingColorSpace(.deviceRGB) ?? c
            return String(format: "%.3f,%.3f,%.3f", d.redComponent, d.greenComponent, d.blueComponent)
        }
        let imageID = image.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue)) } ?? "-"
        return "\(display.rawValue)|\(pattern.rawValue)|\(cloth.rawValue)|\(hex(base))|\(hex(accent))|\(imageID)"
    }

    /// Maps the mesh's material chart (across cm, along cm) to texture space.
    /// On the flat front the narrow end is up, the wide end down, and the
    /// image's right is the viewer's right; the centre line of the tie samples
    /// the horizontal centre of the tile.
    var chartTransform: SCNMatrix4 {
        let diagnostic = display != .fabric
        let rep = diagnostic ? 4.0 : max(repeatCM, 0.1)
        let off = diagnostic ? 0.0 : offsetCM
        let radians = (diagnostic ? 0.0 : angle) * .pi / 180
        let c = cos(radians), n = sin(radians), a = aspect
        var m = SCNMatrix4Identity
        m.m11 = CGFloat(-c / rep); m.m21 = CGFloat(-n / rep); m.m41 = CGFloat(0.5 - off * n / rep)
        m.m12 = CGFloat(-n / (rep * a)); m.m22 = CGFloat(c / (rep * a)); m.m42 = CGFloat(off * c / (rep * a))
        return m
    }
}

enum FabricTexture {
    private static func rgb(_ color: NSColor) -> (Double, Double, Double) {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    static func make(_ settings: FabricSettings, back: Bool = false) -> NSImage {
        if settings.display == .fabric, settings.pattern == .imported, !back, let image = settings.image { return image }
        let size = 1024
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        let base = rgb(settings.base), accent = rgb(settings.accent)
        let paper = (0.88, 0.91, 0.86), ink = (0.22, 0.23, 0.25), mark = (0.95, 0.55, 0.15)
        let teal = (0.08, 0.56, 0.57), rust = (0.80, 0.25, 0.14), grey = (0.34, 0.35, 0.36)
        let bytes = bitmap.bitmapData!
        let shade = back && settings.display != .faces ? 0.72 : 1.0
        for y in 0..<size {
            for x in 0..<size {
                var color = base
                switch settings.display {
                case .grid:
                    color = paper
                    if x % 256 < 6 || y % 256 < 6 { color = ink }
                    if y < 26 { color = mark }
                case .faces:
                    color = back ? rust : teal
                case .fabric:
                    switch settings.pattern {
                    case .imported: color = grey
                    case .stripes: if y < 172 || (y > 210 && y < 240) { color = accent }
                    case .dots:
                        let dx = Double(x % 256) - 128, dy = Double(y % 256) - 128
                        if dx * dx + dy * dy < 400 { color = accent }
                    case .check: if x % 512 < 18 || y % 512 < 18 { color = accent }
                    case .solid: break
                    }
                }
                // A faint twill so plain areas still read as cloth.
                let weave = ((x + y) % 8 < 2 ? 0.95 : 1.0) * shade
                let index = (y * size + x) * 4
                bytes[index] = UInt8(min(255, color.0 * 255 * weave))
                bytes[index + 1] = UInt8(min(255, color.1 * 255 * weave))
                bytes[index + 2] = UInt8(min(255, color.2 * 255 * weave))
                bytes[index + 3] = 255
            }
        }
        if settings.display != .fabric {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 64, weight: .bold),
                .foregroundColor: NSColor.black.withAlphaComponent(0.8),
            ]
            for row in 0..<4 {
                for column in 0..<4 {
                    let label = settings.display == .faces ? (back ? "B ↑" : "F ↑") : "\(row)\(Character(UnicodeScalar(65 + column)!))↑"
                    (label as NSString).draw(at: NSPoint(x: column * 256 + 30, y: row * 256 + 90), withAttributes: attributes)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        return image
    }

    private static func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    }
    private static func image(_ bitmap: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    /// A tileable normal map of the weave: twill ribs for the silks, a
    /// rougher, more open weave for wool.
    static func weaveNormal(_ cloth: ClothKind) -> NSImage {
        let size = 256
        let map = bitmap(size, size)
        let bytes = map.bitmapData!
        func height(_ x: Int, _ y: Int) -> Double {
            let u = Double((x % size + size) % size) / Double(size), v = Double((y % size + size) % size) / Double(size)
            let two = 2 * Double.pi
            switch cloth {
            case .fineSilk: return 0.5 * sin(two * 6 * (u + v))
            case .twill: return 0.5 * sin(two * 4 * (u + v)) + 0.18 * sin(two * 8 * (u - v))
            case .wool:
                let warp = sin(two * 4 * u) * (sin(two * 2 * v) > 0 ? 1 : 0.2)
                let weft = sin(two * 4 * v) * (sin(two * 2 * u) > 0 ? 0.2 : 1)
                let fuzz = sin(two * 17 * u + 3 * sin(two * 5 * v)) * sin(two * 13 * v + 2 * sin(two * 7 * u))
                return 0.4 * warp + 0.4 * weft + 0.22 * fuzz
            }
        }
        let depth = cloth.weaveDepth * Double(size) / 60
        for y in 0..<size {
            for x in 0..<size {
                let dx = (height(x + 1, y) - height(x - 1, y)) * depth, dy = (height(x, y + 1) - height(x, y - 1)) * depth
                let length = (dx * dx + dy * dy + 1).squareRoot()
                let index = (y * size + x) * 4
                bytes[index] = UInt8(max(0, min(255, (-dx / length * 0.5 + 0.5) * 255)))
                bytes[index + 1] = UInt8(max(0, min(255, (dy / length * 0.5 + 0.5) * 255)))
                bytes[index + 2] = UInt8(max(0, min(255, (1 / length * 0.5 + 0.5) * 255)))
                bytes[index + 3] = 255
            }
        }
        return image(map)
    }

    /// The back of the tie, laid out along its whole length: the shell cloth
    /// folded to a centre seam, a contrasting lining at both tips, and the
    /// keeper loop and label behind the blade. u spans 20 cm across, v the
    /// full length from the narrow tip.
    static func lining(_ settings: FabricSettings) -> NSImage {
        let width = 512, height = 2048
        let map = bitmap(width, height)
        let bytes = map.bitmapData!
        let imported = settings.pattern == .imported
        let base = imported ? (0.34, 0.35, 0.36) : rgb(settings.base)
        let accent = imported ? (0.55, 0.56, 0.58) : rgb(settings.accent)
        func shade(_ c: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) { (c.0 * k, c.1 * k, c.2 * k) }
        let shell = shade(base, 0.70), tipping = shade(accent, 0.78), seam = shade(base, 0.42)
        let keeper = shade(base, 0.92), label = (0.86, 0.84, 0.78)
        let length = TieBlank.length
        for y in 0..<height {
            let s = Double(y) / Double(height) * length
            for x in 0..<width {
                let t = (Double(x) / Double(width) - 0.5) * 20
                var color = shell
                if abs(t) < 0.05 { color = seam }
                // Lining shows in a triangle at each tip, as on a real tie.
                if s > length - 11 + abs(t) * 1.0 || s < 6.5 - abs(t) * 1.0 { color = tipping }
                if abs(s - (length - 27)) < 0.55 && abs(t) < 2.6 { color = keeper }
                if abs(s - (length - 31.5)) < 1.1 && abs(t) < 1.7 { color = label }
                let weave = (x + y) % 6 < 2 ? 0.94 : 1.0
                let index = (y * width + x) * 4
                bytes[index] = UInt8(min(255, color.0 * 255 * weave))
                bytes[index + 1] = UInt8(min(255, color.1 * 255 * weave))
                bytes[index + 2] = UInt8(min(255, color.2 * 255 * weave))
                bytes[index + 3] = 255
            }
        }
        return image(map)
    }
}
