import Foundation
import simd

@main struct ClothSafetyChecks {
    static var count=0
    static func check(_ ok:Bool,_ message:String) {count+=1;if !ok {fputs("FAIL: \(message)\n",stderr);exit(1)}}
    static func sheets(_ height:Double=0.01)->ClothMesh {
        let rest=[SIMD2<Double>(0,0),SIMD2(0.1,0),SIMD2(0,0.1),SIMD2(0.3,0),SIMD2(0.4,0),SIMD2(0.3,0.1)]
        return ClothMesh(rest:rest,positions:[V3(0,0,0),V3(0.1,0,0),V3(0,0.1,0),V3(0.01,0.01,height),V3(0.07,0.01,height),V3(0.01,0.07,height)],indices:[[0,1,2],[3,4,5]])
    }
    static func motion(_ mesh:ClothMesh,_ a:[V3],_ b:[V3],thickness:Double=0)->String? {
        var budget=50_000
        return ClothCollision.swept(mesh,a,b,capsules:[],floor:nil,thickness:thickness,budget:&budget)
    }
    static func main() {
        let m=sheets(),start=m.initial
        check(ClothCollision.audit(m,start).intersections.isEmpty,"Separated sheets begin clear")
        var end=start
        for i in 3..<6 {end[i].z = -0.01}
        check(ClothCollision.audit(m,end).intersections.isEmpty,"Fast crossing ends clear too")
        check(motion(m,start,end) != nil,"Swept check catches clear-endpoint tunnelling")
        check(motion(m,start,start.map{$0+V3(1,2,3)},thickness:0.0005)==nil,"Common rigid translation preserves clearance")
        let sliding=sheets(0.0005);var slide=sliding.initial
        for i in 3..<6 {slide[i].x+=0.02}
        check(motion(sliding,sliding.initial,slide,thickness:0.0005)==nil,"Separating plane certifies tangential sliding at thickness")
        let base=Array(start.prefix(3)),piercing=[V3(0.02,0.02,-0.01),V3(0.02,0.02,0.01),V3(0.03,0.02,0.01)]
        check(ClothCollision.intersects(base,piercing),"Edge pierces face interior")
        check(ClothCollision.featureDistance(base,piercing)>0.0005,"Endpoint VF/EE distance can miss a present intersection")
        let coplanar=[V3(0.02,-0.02,0),V3(0.08,0.08,0),V3(-0.02,0.02,0)]
        check(ClothCollision.intersects(base,coplanar),"Coplanar overlap is detected")
        var collapsed=start;collapsed.swapAt(0,1)
        check(motion(m,start,collapsed) != nil,"Triangle collapse between valid endpoints rejected")
        var gap=start;for i in 3..<6 {gap[i].z=0.0003}
        check(motion(m,start,gap,thickness:0.0005) != nil,"Sub-thickness endpoint rejected before intersection")
        // Prescribed grasp motion is part of the swept proposal, even with no dynamics.
        var grasp=ClothSolver(m);grasp.parameters.gravity = .zero;grasp.parameters.selfContact=false
        for i in start.indices {grasp.pins[i]=end[i]}
        let oldV=grasp.velocities
        check(!grasp.advance(),"Crossing grasp command rejected")
        check(grasp.positions==start && grasp.velocities==oldV && grasp.time==0,"Rejected grasp restores position/velocity/time atomically")
        check(grasp.stateValid && grasp.error != nil,"Rejected motion retains an explicitly checked state and failure")
        // Constraint/contact corrections use this same old-to-final acceptance path.
        var proposed=start;for i in 3..<6 {proposed[i].z = -0.002}
        check(motion(m,start,proposed) != nil,"Zero-velocity constraint-shaped crossing is rejected")
        var budget=0
        check(ClothCollision.swept(m,start,start,capsules:[],floor:nil,budget:&budget) != nil,"Exhausted certification budget is a failure")
        let tube=ClothCapsule(a:V3(-1,0,0),b:V3(1,0,0),radius:0.05)
        let above=start.map{V3($0.x,$0.y+0.2,$0.z)},below=start.map{V3($0.x,$0.y-0.2,$0.z)}
        budget=50_000
        check(ClothCollision.swept(m,above,below,capsules:[tube],floor:nil,budget:&budget) != nil,"Swept rounded support crossing rejected")
        let legacy=ClothExperiment.make(.fourInHand,refineSeed:false,prepareSeed:false)
        check(ClothCollision.audit(legacy.mesh,legacy.mesh.initial).intersections.count==2,"Legacy seed defect reproduced on actual solver mesh")
        var invalid=legacy.solver();check(!invalid.advance() && invalid.time==0 && !invalid.stateValid,"Initially intersecting mesh is blocked")
        let refined=ClothExperiment.make(.fourInHand,prepareSeed:false)
        check(ClothCollision.audit(refined.mesh,refined.mesh.initial).intersections.isEmpty,"Two added rows remove geometric crossings")
        let rc=ClothCollision.clearance(refined.mesh,refined.mesh.initial,thickness:0.0005)
        check(rc.violations>0,"Intersection-free is not mistaken for thickness-safe")
        var tooThin=refined.solver();check(!tooThin.advance() && tooThin.time==0,"Insufficient starting thickness blocks advance")
        let prepared=ClothExperiment.make(.fourInHand),pc=ClothCollision.clearance(prepared.mesh,prepared.mesh.initial,thickness:0.0005)
        check(pc.violations==0 && ClothCollision.audit(prepared.mesh,prepared.mesh.initial).intersections.isEmpty,"Contact preparation meets actual seed checks")
        check(prepared.mesh.rest==refined.mesh.rest,"Contact preparation preserves material rest chart")
        var strip=ClothExperiment.make(.strip).solver()
        for _ in 0..<30 {check(strip.advance(),"Controlled support strip continues advancing")}
        check(strip.time>0.49 && simd_distance(strip.positions[100],strip.mesh.initial[100])>0.03,"Checked strip moves substantially; time is not fictitious")
        let pausedP=strip.positions,pausedTime=strip.time;var cancellationChecks=0
        check(!strip.advance(cancelled:{cancellationChecks+=1;return cancellationChecks>2}),"Cancellation interrupts a frame")
        check(strip.positions==pausedP && strip.time==pausedTime && strip.error==nil,"Pause rolls back without making failure permanent")
        check(strip.advance(),"Paused solver resumes with a new checked frame")
        let prior=strip.positions,velocity=strip.velocities,time=strip.time
        for i in prior.indices {strip.pins[i]=prior[i]+V3(0,-2,0)}
        check(!strip.advance(),"Impossible grasp after successful dynamics rejects")
        check(strip.positions==prior && strip.velocities==velocity && strip.time==time,"Last accepted dynamic state retained exactly")
        var fold=ClothExperiment.make(.fold).solver(),contacts=0
        for _ in 0..<30 {
            let old=fold.positions,t=fold.time
            let ok=fold.advance()
            if !ok {print("Fold stopped: \(fold.attemptFailures)")}
            check(ok,"Controlled fold advances through impact")
            check(fold.time>t && fold.positions != old,"Fold acceptance performs actual mechanics")
            check(ClothCollision.audit(fold.mesh,fold.positions).intersections.isEmpty,"Fold accepted state has no nonshared triangle intersections")
            contacts+=fold.snapshot().diagnostics.contacts
        }
        check(contacts>0,"Fold benchmark exercises self-contact response")
        let fc=ClothCollision.clearance(fold.mesh,fold.positions,thickness:fold.parameters.thickness)
        check(fc.violations==0,"Fold maintains finite separation at accepted state")
        print("Fold: time=\(fold.time), min separation=\(fc.minimum), contact corrections=\(contacts), RMS=\(fold.snapshot().diagnostics.strainRMS)")
        var knot=prepared.solver();let initial=knot.positions
        let advanced=knot.advance()
        if advanced {check(ClothCollision.audit(knot.mesh,knot.positions).intersections.isEmpty,"Accepted knot state has no intersections")}
        else {check(knot.positions==initial && knot.time==0 && knot.stateValid,"Bounded knot rejection retains prepared valid state")}
        print("Knot advance=\(advanced), retries=\(knot.retries), evaluations=\(knot.collisionEvaluations), status=\(knot.collisionStatus), error=\(knot.error ?? "none")")
        print("PASS: \(count) collision and acceptance checks")
    }
}
