import Foundation
import simd

@main struct ClothWrapChecks {
    static var count=0
    static func check(_ ok:Bool,_ message:String) {count+=1;if !ok {fputs("FAIL: \(message)\n",stderr);exit(1)}}
    static func main() throws {
        let e=ClothExperiment.make(.wrap),plan=ClothWrapSequence(mesh:e.mesh)
        var solver=e.solver()
        check(solver.parameters.collisionSafety && solver.parameters.thickness==0.0005,"Existing swept guard and thickness retained")
        check(solver.snapshot().diagnostics.strainRMS<1e-12,"Flat initial blank is unstrained")
        check(plan.targets(at:0).allSatisfy{simd_distance($0.value,e.mesh.initial[$0.key])<1e-14},"Initial grasp targets exactly match blank")
        let hold=plan.targets(at:4.25),holdEnd=plan.targets(at:4.75),slideEnd=plan.targets(at:5.25)
        check(hold==holdEnd,"Both grasps remain fixed throughout hold")
        check(hold.allSatisfy{simd_distance(slideEnd[$0.key]!-$0.value,V3(0.005,0,0))<1e-14},"Slide commands exactly 5 mm axially")
        check(ClothWrapSequence.isComplete(5.5) && !ClothWrapSequence.isComplete(5.49),"Sequence has a finite end")
        // Audit interruption must never masquerade as a successful empty audit.
        for stop in [1,100,700] {
            var polls=0
            let audit=ClothCollision.audit(e.mesh,e.mesh.initial,cancelled:{polls+=1;return polls==stop})
            check(audit.interrupted && polls==stop,"One-shot cancellation interrupts audit at poll \(stop)")
            polls=0
            let clearance=ClothCollision.clearance(e.mesh,e.mesh.initial,thickness:0.0005,cancelled:{polls+=1;return polls==stop})
            check(clearance.interrupted,"Clearance audit propagates interruption")
            polls=0
            let planes=ClothCollision.contactPlanes(e.mesh,e.mesh.initial,thickness:0.0005,cancelled:{polls+=1;return polls==stop})
            check(planes.interrupted,"Contact preparation propagates interruption")
            polls=0;var budget=200_000
            check(ClothCollision.swept(e.mesh,e.mesh.initial,e.mesh.initial,capsules:e.capsules,floor:e.floor,thickness:0.0005,budget:&budget,cancelled:{polls+=1;return polls==stop})==ClothCollision.cancellationReason,"Swept check propagates interruption")
        }
        let p=solver.positions,v=solver.velocities,pins=solver.pins
        var predictions=0,once=false
        solver.trace={stage,_ in if stage=="prediction" {predictions+=1}}
        check(!solver.advance(pinTargets:{plan.targets(at:$0)},cancelled:{if predictions>0 && !once {once=true;return true};return false}),"One-shot mid-frame cancellation discards proposal")
        check(solver.positions==p && solver.velocities==v && solver.time==0 && solver.pins==pins && solver.error==nil,"Cancellation exactly restores geometry, velocity, time and grasp targets")
        solver.trace=nil
        check(solver.advance(pinTargets:{plan.targets(at:$0)}),"Cancelled sequence resumes")
        let resumed=solver.positions
        solver.reset();solver.pins=plan.targets(at:0)
        check(solver.positions==p && solver.velocities==v && solver.time==0 && solver.attemptFailures.isEmpty,"Reset restores flat state and clears attempt history")
        check(solver.advance(pinTargets:{plan.targets(at:$0)}) && solver.positions==resumed,"Reset replay is deterministic")
        // A prescribed rigid translation verifies callback timing independently
        // of the wrap shape. Every target is checked by the existing swept guard.
        var translated=e.solver();translated.capsules=[];translated.floor=nil
        translated.pins=Dictionary(uniqueKeysWithValues:p.enumerated().map{($0.offset,$0.element)})
        var sampled:[Double]=[]
        check(translated.advance(pinTargets:{time in sampled.append(time);return Dictionary(uniqueKeysWithValues:p.enumerated().map{($0.offset,$0.element+V3(time*0.06,0,0))})}),"Safe prescribed rigid translation accepted")
        check(sampled.count==12 && abs(sampled[0]-1.0/720)<1e-12 && abs(sampled.last!-1.0/60)<1e-12,"Grasps sampled each substep, not once per frame")
        check(zip(translated.positions,p).allSatisfy{simd_distance($0-$1,V3(0.001,0,0))<1e-12},"Accepted target motion is real geometry displacement")
        // A moving target that crosses the mandrel must still fail atomically.
        var unsafe=e.solver()
        check(!unsafe.advance(pinTargets:{_ in Dictionary(uniqueKeysWithValues:p.enumerated().map{($0.offset,$0.element+V3(0,-0.1,0))})}),"Crossing scripted targets are rejected by unchanged guard")
        check(unsafe.positions==p && unsafe.pins==pins && unsafe.time==0 && unsafe.error != nil,"Rejected scripted targets restore original pins and state")
        print("PASS: \(count) staged-grasp, audit cancellation, rollback and reset checks")
    }
}
