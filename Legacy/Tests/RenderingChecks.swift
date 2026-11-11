import Foundation
import AppKit
import SceneKit
import simd

@main
struct RenderingChecks {
    static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let directory=CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "artifacts/v0.3-tests"
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        var count=0
        func check(_ condition:Bool,_ message:String) { count+=1; if !condition { fputs("FAIL: \(message)\n",stderr);exit(1) } }
        func load(_ name:String)throws->NSImage { try FabricImage.load(URL(fileURLWithPath:"Tests/Fixtures/\(name)")) }
        check((try? FabricImage.load(URL(fileURLWithPath:"Tests/Fixtures/missing-image.png"))) == nil,"unreadable swatch returns an error")
        let regular=try load("orientation.png"),dpi=try load("orientation-dpi.png"),rotated=try load("orientation-exif6.jpg")
        check(FabricImage.pixelSize(regular)==NSSize(width:512,height:256),"regular pixel dimensions")
        check(FabricImage.pixelSize(dpi)==NSSize(width:512,height:256),"unequal DPI does not change aspect")
        check(FabricImage.pixelSize(rotated)==NSSize(width:256,height:512),"EXIF 6 rotates dimensions once")
        func color(_ image:NSImage,_ x:Int,_ y:Int)->[Double] {
            let bitmap=NSBitmapImageRep(cgImage:image.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
            let c=bitmap.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
            return [c.redComponent,c.greenComponent,c.blueComponent]
        }
        func same(_ a:[Double],_ b:[Double],tolerance:Double=0.07)->Bool { zip(a,b).allSatisfy{abs($0-$1)<tolerance} }
        check(same(color(regular,80,60),color(dpi,80,60)),"DPI keeps pixels")
        // EXIF 6 is clockwise: old bottom-left becomes new top-left.
        check(same(color(rotated,60,80),color(regular,80,196)),"EXIF 6 normalizes actual colored pixels")
        let originalPoints=[(80,60),(420,60),(80,196),(420,196)]
        for orientation in 1...8 {
            let image=try load("orientation-exif\(orientation).jpg")
            check(FabricImage.pixelSize(image)==(orientation<5 ? NSSize(width:512,height:256) : NSSize(width:256,height:512)),"EXIF \(orientation) pixel aspect")
            for (x,y) in originalPoints {
                let destination:[(Int,Int)]=[(x,y),(511-x,y),(511-x,255-y),(x,255-y),(y,x),(255-y,x),(255-y,511-x),(y,511-x)]
                let (dx,dy)=destination[orientation-1]
                check(same(color(image,dx,dy),color(regular,x,y)),"EXIF \(orientation) quadrant orientation")
            }
        }
        let fabric=FabricSettings(pattern:.imported,repeatCM:4,offsetCM:0,angle:0,image:regular)
        check(abs(fabric.aspect-0.5)<1e-10,"non-square repeat height")
        let reverse=FabricTexture.make(fabric,back:true)
        check(same(color(reverse,80,80),color(reverse,400,400),tolerance:0.03),"unknown reverse has no imported quadrant artwork")
        check(!same(color(reverse,80,80),color(regular,80,60)),"reverse differs from front image")
        let mesh=PremadeFourInHand.build().mesh
        let scene=SceneFactory.make(SceneSettings(fabric:fabric,camera:"Knot"))
        let geometry=scene.rootNode.childNode(withName:"authored-fabric-panels",recursively:false)!.geometry!
        let source=geometry.sources(for:.texcoord).first!
        check(source.vectorCount==mesh.positions.count,"SceneKit contains every mesh UV")
        func read(_ row:Int,_ component:Int)->Double {
            let offset=source.dataOffset+row*source.dataStride+component*source.bytesPerComponent
            return source.data.withUnsafeBytes { bytes in source.bytesPerComponent==8 ? bytes.loadUnaligned(fromByteOffset:offset,as:Double.self) : Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)) }
        }
        for i in stride(from:0,to:source.vectorCount,by:37) {
            // Independent oracle reads the uploaded SceneKit buffer, not a UV-helper result.
            check(abs(read(i,0)-(0.5-mesh.chart[i].x/4))<1e-5 && abs(read(i,1)-mesh.chart[i].y/2)<1e-5,"actual SceneKit UV encodes non-square imported tile")
        }
        var shifted=SceneSettings(fabric:fabric,camera:"Knot");shifted.spread=2;shifted.fabric.angle=35;shifted.fabric.offsetCM=0.7;shifted.fabric.repeatCM=3
        let shiftedScene=SceneFactory.make(shifted)
        let transformed=shiftedScene.rootNode.childNode(withName:"authored-fabric-panels",recursively:false)!.geometry!.sources(for:.texcoord).first!
        for i in stride(from:0,to:transformed.vectorCount,by:503) {
            let value=transformed.data.withUnsafeBytes { bytes -> SIMD2<Double> in
                let offset=transformed.dataOffset+i*transformed.dataStride
                if transformed.bytesPerComponent==8 { return SIMD2(bytes.loadUnaligned(fromByteOffset:offset,as:Double.self),bytes.loadUnaligned(fromByteOffset:offset+8,as:Double.self)) }
                return SIMD2(Double(bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)),Double(bytes.loadUnaligned(fromByteOffset:offset+4,as:Float.self)))
            }
            let right = -mesh.chart[i].x, s=mesh.chart[i].y+0.7,theta=35*Double.pi/180
            check(abs(value.x-(0.5+(right*cos(theta)-s*sin(theta))/3))<1e-5 && abs(value.y-(right*sin(theta)+s*cos(theta))/1.5)<1e-5,"actual transformed SceneKit UV preserves chart through layer separation")
        }
        // A known front-facing flat strip uses the exact production mesh/material path.
        let samples=[RibbonSample(center:V3(0,1,0),across:V3(-1,0,0),normal:V3(0,0,1),width:4,s:0,phase:-1),RibbonSample(center:V3(0,-1,0),across:V3(-1,0,0),normal:V3(0,0,1),width:4,s:2,phase:-1)]
        let flat=RibbonMesh(RibbonModel(kind:.fourInHand,samples:samples,crossings:[]),refined:false)
        let flatScene=SCNScene();flatScene.background.contents=NSColor.black
        let g=SceneFactory.geometry(flat,fabric:fabric);g.materials.forEach{$0.lightingModel = .constant}
        flatScene.rootNode.addChildNode(SCNNode(geometry:g))
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=1.5;camera.position=SCNVector3(0,0,10);flatScene.rootNode.addChildNode(camera)
        let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=flatScene;renderer.pointOfView=camera
        let cases:[(String,Double,Double,Double)]=[("orientation-flat",4,0,0),("orientation-repeat-offset",2,0.5,0),("orientation-angle",3,0.7,35)]
        for (name,repeatCM,offset,angle) in cases {
            var settings=fabric;settings.repeatCM=repeatCM;settings.offsetCM=offset;settings.angle=angle
            let altered=SceneFactory.geometry(flat,fabric:settings);altered.materials.forEach{$0.lightingModel = .constant}
            flatScene.rootNode.childNodes.first!.geometry=altered
            let image=renderer.snapshot(atTime:0,with:NSSize(width:640,height:480),antialiasingMode:.multisampling4X)
            let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent("\(name).png"))
            var compared=0,matching=0
            for x in stride(from:42,to:620,by:37) { for y in stride(from:102,to:390,by:37) {
                let right=Double(x)/160-2,down=Double(y-80)/160
                let theta=angle*Double.pi/180
                let u=0.5+(right*cos(theta)-(down+offset)*sin(theta))/repeatCM
                let v=(right*sin(theta)+(down+offset)*cos(theta))/(repeatCM*0.5)
                let px=Int((u-floor(u))*512),py=Int((v-floor(v))*256)
                // Tolerate antialiasing at letter edges, but compare the complete
                // asymmetric color/text field at independently predicted pixels.
                compared+=1
                if same(color(image,x,y),color(regular,px,py),tolerance:0.15) { matching+=1 }
            }}
            check(Double(matching)/Double(compared)>0.94,"rendered \(name) orientation/scale/offset: \(matching)/\(compared) samples")
            print("\(name): \(matching)/\(compared) independent pixel samples matched")
        }
        flatScene.rootNode.childNodes.first!.geometry=g
        camera.position=SCNVector3(0,0,-10);camera.eulerAngles=SCNVector3(0,CGFloat.pi,0)
        let back=renderer.snapshot(atTime:0,with:NSSize(width:640,height:480),antialiasingMode:.multisampling4X)
        check(same(color(back,120,150),color(back,520,330),tolerance:0.03),"rendered reverse is uniform neutral, not duplicated artwork")
        check(!same(color(back,120,150),color(regular,80,60)),"front artwork absent from rendered reverse")
        try NSBitmapImageRep(data:back.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent("orientation-reverse.png"))
        print("PASS: \(count) decoding, EXIF, material-side, actual SceneKit-buffer and rendered-pixel checks")
    }
}
