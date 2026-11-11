import AppKit
import ImageIO

enum FabricImageError: Error, LocalizedError {
    case unreadable
    var errorDescription: String? { "This image could not be decoded. Choose a PNG, JPEG, TIFF or HEIC swatch." }
}

enum FabricImage {
    /// Normalize EXIF orientation once. Pixel dimensions, never DPI-dependent
    /// NSImage point dimensions, determine the physical tile aspect ratio.
    static func load(_ url: URL) throws -> NSImage {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let raw=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw FabricImageError.unreadable }
        let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
        let orientation=(properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let w=CGFloat(raw.width),h=CGFloat(raw.height)
        let swap=(5...8).contains(orientation), dw=swap ? h:w, dh=swap ? w:h
        let scale=min(1,4096/max(dw,dh)), outW=max(1,Int(dw*scale)),outH=max(1,Int(dh*scale))
        guard let context=CGContext(data:nil,width:outW,height:outH,bitsPerComponent:8,bytesPerRow:outW*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw FabricImageError.unreadable }
        // ImageIO's thumbnail transform also corrects non-square DPI, which can
        // distort a swatch. Apply only the EXIF orientation, in pixel space.
        let transforms:[CGAffineTransform] = [
            .identity,
            CGAffineTransform(a:-1,b:0,c:0,d:1,tx:w,ty:0),
            CGAffineTransform(a:-1,b:0,c:0,d:-1,tx:w,ty:h),
            CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:h),
            CGAffineTransform(a:0,b:-1,c:-1,d:0,tx:h,ty:w),
            CGAffineTransform(a:0,b:-1,c:1,d:0,tx:0,ty:w),
            CGAffineTransform(a:0,b:1,c:1,d:0,tx:0,ty:0),
            CGAffineTransform(a:0,b:1,c:-1,d:0,tx:h,ty:0)
        ]
        context.scaleBy(x:CGFloat(outW)/dw,y:CGFloat(outH)/dh)
        context.concatenate(transforms[min(8,max(1,orientation))-1])
        context.draw(raw,in:CGRect(x:0,y:0,width:w,height:h))
        guard let image=context.makeImage() else { throw FabricImageError.unreadable }
        return NSImage(cgImage:image,size:NSSize(width:outW,height:outH))
    }

    static func pixelSize(_ image:NSImage)->NSSize {
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return image.size }
        return NSSize(width:cg.width,height:cg.height)
    }
}
