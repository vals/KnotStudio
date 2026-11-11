import Foundation
import simd
@main struct ClothWrapProbe {
    static func main() throws {
        let directory=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"artifacts/cloth-0.7"
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        let e=ClothExperiment.make(.wrap),plan=ClothWrapSequence(mesh:e.mesh)
        var s=e.solver(),records:[[String:Any]]=[]
        let started=Date(),frames=Int((ClothWrapSequence.duration*60).rounded())
        for frame in 0...frames {
            let before=s.positions,oldTime=s.time
            let accepted=frame==0 || s.advance(pinTargets:{plan.targets(at:$0)})
            let m=ClothWrapSequence.metrics(s),d=s.snapshot().diagnostics
            let clearance=ClothCollision.clearance(e.mesh,s.positions,thickness:s.parameters.thickness)
            precondition(!clearance.interrupted && clearance.violations==0,"Accepted mesh violated thickness")
            let record:[String:Any]=["state_valid":s.stateValid,"collision_safety":s.parameters.collisionSafety,"thickness_m":s.parameters.thickness,"clearance_violations":clearance.violations,"collision_status":s.collisionStatus,"frame":frame,"time":s.time,"phase":ClothWrapSequence.phase(s.time),"accepted":accepted,"rms":d.strainRMS,"shear":d.shearMax,"speed":d.maxSpeed,"contacts":m.nearContactVertices,"contact_triangles":m.nearContactTriangles,"triangle_support_gap":m.minimumTriangleSupportGap,"support_gap":m.minimumSupportGap,"angular_span":m.angularSpan,"near_support_arc":m.nearSupportArc,"mean_free_x":m.meanFreeX,"retries":s.retries,"collision_evaluations":s.collisionEvaluations]
            records.append(record)
            precondition(d.strainRMS<0.05,"Wrap exceeds 5% RMS strain benchmark limit")
            precondition(m.minimumTriangleSupportGap >= -1e-10,"Accepted frame penetrates nominal support shell")
            if s.time>=4.25-1e-9 {precondition(m.nearContactTriangles>=100 && d.strainRMS<0.01,"Wrap loses held contact or exceeds 1% RMS strain after forming")}
            if frame%15==0 || !accepted {
                print(String(format:"frame %d t %.4f %@ RMS %.5f shear %.2f contacts %d gap %.6f faces %d facegap %.9f arc %.1f/%.1f retry %d wall %.1f",frame,s.time,ClothWrapSequence.phase(s.time),d.strainRMS,d.shearMax,m.nearContactVertices,m.minimumSupportGap,m.nearContactTriangles,m.minimumTriangleSupportGap,m.nearSupportArc,m.angularSpan,s.retries,Date().timeIntervalSince(started)));fflush(stdout)
            }
            if [0,15,75,135,195,255,285,315,330].contains(frame) || !accepted {
                let snapshot:[String:Any]=["positions_m":s.positions.map{[$0.x,$0.y,$0.z]},"rest_m":e.mesh.rest.map{[$0.x,$0.y]},"triangles":e.mesh.triangles.map{$0.ids},"time":s.time,"metrics":record,"pins":s.pins.keys.sorted(),"error":s.error ?? "","collision_status":s.collisionStatus,"state_valid":s.stateValid]
                try JSONSerialization.data(withJSONObject:snapshot,options:[.sortedKeys]).write(to:URL(fileURLWithPath:directory).appendingPathComponent("wrap-\(frame).json"))
            }
            if !accepted {print("STOP: \(s.error ?? "paused") retained=\(before==s.positions && oldTime==s.time) attempts=\(s.attemptFailures)");break}
        }
        try JSONSerialization.data(withJSONObject:records,options:[.sortedKeys]).write(to:URL(fileURLWithPath:directory).appendingPathComponent("wrap-history.json"))
        guard ClothWrapSequence.isComplete(s.time) else {fputs("FAIL: sequence stopped before completion\n",stderr);exit(1)}
        let holdStart=records[255],holdEnd=records[285],slideEnd=records[315]
        let displacement=(slideEnd["mean_free_x"] as! Double)-(holdEnd["mean_free_x"] as! Double)
        precondition(displacement>0.0005,"No measurable free-cloth axial slide")
        print("PASS: 330 accepted frames, 5.5 s; held face contact \(holdStart["contact_triangles"]!)–\(holdEnd["contact_triangles"]!); free-cloth mean slide \(displacement*1000) mm")
    }
}
