import Foundation
import AppKit
import SceneKit

@main struct ClothRender {
    static func main() throws {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        let directory=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"artifacts/cloth-0.5"
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        // The staged wrap has its own deterministic probe and saved-state renderer.
        for kind in [ClothCase.strip,.fold,.fourInHand] {
            let experiment=ClothExperiment.make(kind);var solver=experiment.solver()
            var initialTexture:Data?
            let frames=kind == .strip ? [0,30,90]:kind == .fold ? [0,15,30]:[0,1,3]
            for frame in 0...frames.last! {
                let rejected=frame>0 && !solver.advance()
                if rejected {print("\(kind.rawValue): \(solver.error ?? "rejected")")}
                if !frames.contains(frame) && !rejected {continue}
                let prefix=kind == .strip ? "strip":kind == .fold ? "fold":"four-in-hand-seed"
                let stem=prefix+(rejected ? "-retained":"-\(frame)")
                let snapshot=solver.snapshot(),d=snapshot.diagnostics
                var fabric=FabricSettings();fabric.pattern = .ruler;fabric.angle=0;fabric.repeatCM=4
                let scene=ClothSceneFactory.make(experiment:experiment,positions:snapshot.positions,fabric:fabric,pins:snapshot.pins)
                let texture=scene.rootNode.childNode(withName:"cloth",recursively:false)!.geometry!.sources(for:.texcoord).first!.data
                if let initialTexture=initialTexture {precondition(texture==initialTexture,"Rendered material coordinates changed during solve")}
                else {initialTexture=texture}
                let renderer=SCNRenderer(device:nil,options:nil);renderer.scene=scene;renderer.pointOfView=scene.rootNode.childNode(withName:"camera",recursively:false)
                let image=renderer.snapshot(atTime:0,with:NSSize(width:1200,height:1000),antialiasingMode:.multisampling4X)
                let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
                try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent(stem+".png"))
                if kind == .fourInHand && frame>0 {
                    let close=ClothSceneFactory.make(experiment:experiment,positions:snapshot.positions,fabric:fabric,camera:"Knot",pins:snapshot.pins)
                    renderer.scene=close;renderer.pointOfView=close.rootNode.childNode(withName:"camera",recursively:false)
                    let im=renderer.snapshot(atTime:0,with:NSSize(width:1000,height:1000),antialiasingMode:.multisampling4X)
                    let bm=NSBitmapImageRep(data:im.tiffRepresentation!)!
                    try bm.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent("four-in-hand-seed-close.png"))
                }
                let json:[String:Any]=["time":snapshot.time,"positions_m":snapshot.positions.map{[$0.x,$0.y,$0.z]},"rest_m":experiment.mesh.rest.map{[$0.x,$0.y]},"triangles":experiment.mesh.triangles.map{$0.ids},"collision_status":snapshot.collisionStatus,"state_valid":snapshot.stateValid,"error":snapshot.error ?? "","diagnostics":["rms_strain":d.strainRMS,"warp_min":d.warpMin,"warp_max":d.warpMax,"weft_min":d.weftMin,"weft_max":d.weftMax,"shear_max_degrees":d.shearMax,"contacts":d.contacts,"max_speed_m_s":d.maxSpeed,"minimum_external_gap_m":d.minExternalGap]]
                try JSONSerialization.data(withJSONObject:json,options:[.sortedKeys]).write(to:URL(fileURLWithPath:directory).appendingPathComponent(stem+".json"))
                print(String(format:"%@ frame %d: t=%.4f RMS=%.5f shearMax=%.2f speed=%.4f",kind.rawValue,frame,snapshot.time,d.strainRMS,d.shearMax,d.maxSpeed))
                fflush(stdout)
                if rejected {break}
            }
        }
        print("PASS: actual rendered material-coordinate buffers unchanged across every emitted solver snapshot")
    }
}
