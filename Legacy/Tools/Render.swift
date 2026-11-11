import Foundation
import AppKit
import SceneKit

@main
struct Render {
    static func main() throws {
        // Offscreen renderer: no windows, launch activation, or native UI automation.
        let directory=CommandLine.arguments.dropFirst().first ?? "artifacts/revision"
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        let modes=CommandLine.arguments.count > 2 ? CommandLine.arguments[2].components(separatedBy:",") : ["gray","gray-side","dots","dots-side","fabric","side"]
        let preset=PremadeFourInHand.build()
        let legacy=FourInHand.build()
        let mesh=modes == ["legacy-mesh"] ? RibbonMesh(legacy):preset.mesh
        var payload:[String:Any] = ["model":modes == ["legacy-mesh"] ? "legacy route":"authored preset", "positions":mesh.positions.map{[$0.x,$0.y,$0.z]},"front":mesh.front,"back":mesh.back,"edges":mesh.edges,"chart":mesh.chart.map{[$0.x,$0.y]},"row_width":mesh.rowWidth,"row_count":mesh.rowCount,"parts":preset.parts.map{["name":$0.name,"first":$0.first,"count":$0.count,"rows":$0.rows,"columns":$0.columns] as [String:Any]}]
        if modes == ["legacy-mesh"] {
            payload["phases"]=legacy.samples.map{$0.phase}
            payload["parts"]=[]
            let rows=legacy.samples.map{s in [s.center.x,s.center.y,s.center.z,s.across.x,s.across.y,s.across.z,s.normal.x,s.normal.y,s.normal.z,s.width,s.s,Double(s.phase)]}
            try JSONSerialization.data(withJSONObject:rows).write(to:URL(fileURLWithPath:directory).appendingPathComponent("ribbon.json"))
        }
        try JSONSerialization.data(withJSONObject:payload).write(to:URL(fileURLWithPath:directory).appendingPathComponent("surface.json"))
        if modes == ["mesh"] || modes == ["legacy-mesh"] { print("Exported \(payload["model"]!) mesh to \(directory)"); return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        for requestedMode in modes {
            let mode=requestedMode.replacingOccurrences(of:"legacy-",with:"")
            var s=SceneSettings(); s.knot = .fourInHand; s.camera="Knot"
            if requestedMode.hasPrefix("legacy-") {s.premade=false}
            if mode=="routing" { s.fabric.pattern = .ruler; s.fabric.angle=0; s.showPath=true; s.spread=1.0 }
            if mode=="faces" { s.fabric.pattern = .faces; s.fabric.angle=0 }
            if mode=="offset" || mode=="baseline" { s.fabric.offsetCM = 1.8 }
            if mode=="baseline" { s.refined = false }
            if mode=="gray" {s.fabric.pattern = .solid;s.fabric.base = NSColor(srgbRed:0.48,green:0.49,blue:0.50,alpha:1)}
            if mode=="dots" {s.fabric.pattern = .dots;s.fabric.angle=0;s.fabric.repeatCM=2.0}
            if mode=="check" {s.fabric.pattern = .check;s.fabric.angle=0;s.fabric.repeatCM=2.0}
            if mode=="grid" { s.fabric.pattern = .ruler; s.fabric.angle=0 }
            if mode.hasPrefix("imported") || mode=="flat" {
                s.fabric.pattern = .imported
                s.fabric.image = try FabricImage.load(URL(fileURLWithPath:"Tests/Fixtures/orientation.png"))
                s.fabric.angle=0;s.fabric.repeatCM=4
                if mode=="imported-shift" { s.fabric.offsetCM=0.75;s.fabric.repeatCM=2.5 }
                if mode=="imported-angle" { s.fabric.angle=35 }
                if mode=="flat" { s.camera="Flat" }
            }
            if mode.contains("side") {s.camera="Side"}
            if mode.hasPrefix("gray") {s.fabric.pattern = .solid;s.fabric.base = NSColor(srgbRed:0.48,green:0.49,blue:0.50,alpha:1)}
            if mode.hasPrefix("dots") {s.fabric.pattern = .dots;s.fabric.angle=0;s.fabric.repeatCM=2.0}
            if mode.hasPrefix("check") {s.fabric.pattern = .check;s.fabric.angle=0;s.fabric.repeatCM=2.0}
            if mode=="portrait" { s.camera="Portrait" }
            let scene=SceneFactory.make(s), renderer=SCNRenderer(device:nil,options:nil)
            let camera=scene.rootNode.childNode(withName:"camera",recursively:false)!
            if requestedMode.hasPrefix("legacy-") {
                camera.camera?.orthographicScale=4.7
                camera.camera?.screenSpaceAmbientOcclusionIntensity=0.85
                camera.camera?.screenSpaceAmbientOcclusionRadius=1.4
                camera.camera?.screenSpaceAmbientOcclusionBias=0.035
            }
            if mode=="back" { camera.position=SCNVector3(0,0.5,-40); camera.eulerAngles=SCNVector3(0,CGFloat.pi,0) }
            renderer.scene=scene; renderer.pointOfView=camera
            let snapshot=renderer.snapshot(atTime:0,with:NSSize(width:1100,height:1100),antialiasingMode:.multisampling4X)
            let bitmap=NSBitmapImageRep(data:snapshot.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent("four-in-hand-\(requestedMode).png"))
        }
        print("Rendered \(modes.count) offscreen previews to \(directory)")
    }
}
