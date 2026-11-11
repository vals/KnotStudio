import AppKit

enum FabricPattern: String, CaseIterable, Identifiable {
    case stripes = "Regimental", dots = "Pin dots", check = "Windowpane", solid = "Solid", ruler = "Material grid", faces = "Front / back", imported = "Imported image"
    var id: String { rawValue }
}
struct FabricSettings {
    var pattern: FabricPattern = .stripes
    var base: NSColor = NSColor(srgbRed:0.08, green:0.18, blue:0.28, alpha:1)
    var accent: NSColor = NSColor(srgbRed:0.88, green:0.63, blue:0.28, alpha:1)
    var repeatCM: Double = 3.6
    var offsetCM: Double = 0
    var angle: Double = 32
    var image: NSImage?
    var aspect: Double { guard pattern == .imported, let image = image else { return 1 }; let size=FabricImage.pixelSize(image); return size.height / max(1,size.width) }
}

enum FabricTexture {
    static func make(_ settings: FabricSettings, back: Bool = false) -> NSImage {
        if settings.pattern == .imported, !back, let image = settings.image { return image }
        let size = 512
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
        let base = settings.base.usingColorSpace(.deviceRGB)!, accent = settings.accent.usingColorSpace(.deviceRGB)!
        for y in 0..<size { for x in 0..<size {
            var color = base
            switch settings.pattern {
            case .imported:
                // The front image supplies no evidence about the reverse.
                color = NSColor(srgbRed:0.34,green:0.35,blue:0.36,alpha:1)
            case .stripes:
                if (y % size) < 86 || (y > 105 && y < 120) { color = accent }
            case .dots:
                let dx = Double(x % 128) - 64, dy = Double(y % 128) - 64
                if dx*dx+dy*dy < 100 { color = accent }
            case .check:
                if x % 256 < 9 || y % 256 < 9 { color = accent }
            case .ruler:
                color = NSColor(srgbRed:0.88,green:0.91,blue:0.86,alpha:1)
                if x % 128 < 3 || y % 128 < 3 { color = .darkGray }
                if y < 13 { color = .systemOrange }
            case .faces: color = back ? NSColor(srgbRed:0.8,green:0.25,blue:0.14,alpha:1) : NSColor(srgbRed:0.08,green:0.56,blue:0.57,alpha:1)
            default: break
            }
            let rgb = color.usingColorSpace(.deviceRGB)!
            let weave = ((x+y) % 4 == 0 ? 0.94 : 1.0) * (back && settings.pattern != .faces ? 0.76 : 1)
            let index = (y*size+x)*4, bytes = bitmap.bitmapData!
            bytes[index] = UInt8(min(255,rgb.redComponent*255*weave))
            bytes[index+1] = UInt8(min(255,rgb.greenComponent*255*weave))
            bytes[index+2] = UInt8(min(255,rgb.blueComponent*255*weave))
            bytes[index+3] = 255
        }}
        if settings.pattern == .ruler || settings.pattern == .faces {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
            let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:34,weight:.bold),.foregroundColor:NSColor.black]
            for row in 0..<4 { for column in 0..<4 {
                let label = settings.pattern == .faces ? (back ? "B ↑" : "F ↑") : "\(row)\(Character(UnicodeScalar(65+column)!))↑"
                (label as NSString).draw(at:NSPoint(x:column*128+14,y:row*128+44),withAttributes:attributes)
            }}
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size:NSSize(width:size,height:size)); image.addRepresentation(bitmap); return image
    }
}
