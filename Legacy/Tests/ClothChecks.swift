import Foundation
import simd

@main struct ClothChecks {
    static var checks=0
    static func expect(_ condition:Bool,_ message:String) {checks+=1;if !condition {fputs("FAIL: \(message)\n",stderr);exit(1)}}
    static func near(_ a:Double,_ b:Double,_ tolerance:Double,_ message:String) {expect(abs(a-b)<tolerance,"\(message): \(a) vs \(b)")}
    static func patch()->ClothMesh {
        let r=[SIMD2<Double>(0,0),SIMD2(0.1,0),SIMD2(0,0.1),SIMD2(0.1,0.1)]
        return ClothMesh(rest:r,positions:r.map{V3($0.x,$0.y,0)},indices:[[0,1,2],[1,3,2]])
    }
    static func main() {
        let m=patch(),rotation=simd_quatd(angle:0.84,axis:unit(V3(1,2,3)))
        for p in [m.initial,m.initial.map{rotation.act($0)+V3(0.3,-0.2,0.6)}] {
            for t in m.triangles {for mode in 0..<3 {near(t.constraint(mode,p).0,0,1e-12,"Rest/rigid material invariant")}}
            for h in m.hinges {near(h.constraint(p).0,0,1e-12,"Flat/rigid bending invariant")}
        }
        let deformed=[V3(0.01,-0.02,0.02),V3(0.14,0.02,-0.01),V3(-0.01,0.11,0.07),V3(0.09,0.09,0.10)]
        for t in m.triangles {for mode in 0..<3 {gradient(ids:t.ids,p:deformed,eval:{t.constraint(mode,$0)},name:"strain \(mode)")}}
        for h in m.hinges {gradient(ids:h.ids,p:deformed,eval:{h.constraint($0)},name:"dihedral")}
        for mode in 0..<3 {
            var s=ClothSolver(m);s.parameters.gravity = .zero;s.parameters.selfContact=false;s.parameters.bending=0
            s.positions=m.initial.map{mode==0 ? V3($0.x*1.15,$0.y,0):mode==1 ? V3($0.x,$0.y*1.15,0):V3($0.x+$0.y*0.2,$0.y,0)}
            let before=s.snapshot().diagnostics.strainRMS
            for _ in 0..<40 {expect(s.advance(),"Membrane advance")}
            expect(s.snapshot().diagnostics.strainRMS<before*0.1,"Independent strain mode relaxes")
        }
        var bend=ClothSolver(m);bend.parameters.gravity = .zero;bend.parameters.selfContact=false;bend.parameters.damping=8
        let a=m.initial[1],axis=unit(m.initial[2]-a),q=simd_quatd(angle:0.7,axis:axis)
        bend.positions[3]=a+q.act(m.initial[3]-a)
        near(bend.snapshot().diagnostics.strainRMS,0,1e-12,"Isometric hinge starts without membrane strain")
        let startAngle=abs(m.hinges[0].constraint(bend.positions).0)
        for _ in 0..<90 {expect(bend.advance(),"Bending advance")}
        expect(abs(m.hinges[0].constraint(bend.positions).0)<startAngle*0.8,"Dihedral bending relaxes")
        expect(bend.snapshot().diagnostics.strainRMS<0.015,"Bending preserves intrinsic metric")
        contactChecks()
        let e=ClothExperiment.make(.strip)
        var strip=e.solver();let original=e.mesh.rest
        for _ in 0..<90 {expect(strip.advance(),"Strip drape advances")}
        let d=strip.snapshot().diagnostics
        expect(d.minExternalGap > -0.0001,"Rounded support/floor penetration bounded")
        expect(d.strainRMS<0.06,"Strip strain remains bounded")
        expect(strip.mesh.rest==original,"Material chart immutable under solve")
        print(String(format:"Strip at %.3f s: RMS strain %.5f, warp %.4f..%.4f, weft %.4f..%.4f, shear %.2f deg, external gap %.6f m",strip.time,d.strainRMS,d.warpMin,d.warpMax,d.weftMin,d.weftMax,d.shearMax,d.minExternalGap))
        strip.reset();expect(strip.positions==e.mesh.initial && strip.time==0 && strip.error==nil,"Reset restores initial state")
        var fresh=e.solver();expect(strip.advance() && fresh.advance(),"Reset advances")
        expect(strip.positions==fresh.positions,"Reset deterministic")
        var coarse=e.solver(),fine=e.solver();coarse.parameters.selfContact=false;fine.parameters.selfContact=false
        coarse.parameters.substeps=6;fine.parameters.substeps=12
        for _ in 0..<30 {expect(coarse.advance() && fine.advance(),"Timestep comparison")}
        var totalDifference=0.0
        for i in coarse.positions.indices {totalDifference+=simd_length(coarse.positions[i]-fine.positions[i])}
        let difference=totalDifference/Double(coarse.positions.count)
        print(String(format:"Default 6 vs 12 substeps at 0.5 s: mean position difference %.6f m",difference))
        expect(difference<0.003,"Small-step sensitivity bounded to 3 mm over 0.5 s")
        var grasp=e.grasp;let before=grasp.targets;grasp.position+=V3(0,0.01,0)
        for (i,p) in grasp.targets {near(simd_length(p-before[i]!-V3(0,0.01,0)),0,1e-12,"Grasp patch translates rigidly")}
        grasp.held=false;expect(grasp.targets.isEmpty,"Release removes grasp constraints")
        let knot=ClothExperiment.make(.fourInHand);var knotSolver=knot.solver()
        let kd=knotSolver.snapshot().diagnostics
        print(String(format:"Four-in-hand INITIAL RMS %.5f, warp %.3f..%.3f, weft %.3f..%.3f, shear %.2f deg; %d vertices",kd.strainRMS,kd.warpMin,kd.warpMax,kd.weftMin,kd.weftMax,kd.shearMax,knot.mesh.initial.count))
        expect(kd.strainRMS>0.05,"Authored strain is visible, not encoded as rest")
        for _ in 0..<3 {
            let p=knotSolver.positions,t=knotSolver.time
            if knotSolver.advance() {
                expect(knotSolver.positions != p && knotSolver.time>t,"Accepted knot step performs real dynamics")
                expect(ClothCollision.audit(knot.mesh,knotSolver.positions).intersections.isEmpty,"Accepted knot step has no nonshared crossings")
            } else {
                expect(knotSolver.positions==p && knotSolver.time==t && knotSolver.stateValid,"Rejected knot frame retains checked seed/state")
                break
            }
        }
        print("Four-in-hand: \(knotSolver.collisionStatus)")
        expect(knotSolver.mesh.rest==knot.mesh.rest,"Knot solve preserves chart even on rejection")
        print("PASS: \(checks) cloth checks; discrete tunnelling limitation explicitly reproduced")
    }
    static func gradient(ids:[Int],p:[V3],eval:([V3])->(Double,[V3]),name:String) {
        let analytic=eval(p).1,epsilon=1e-7
        for (j,i) in ids.enumerated() {for axis in 0..<3 {
            var a=p,b=p;a[i][axis]+=epsilon;b[i][axis]-=epsilon
            let numerical=(eval(a).0-eval(b).0)/(2*epsilon)
            near(analytic[j][axis],numerical,1e-5*max(1,abs(numerical)),"\(name) gradient")
        }}
    }
    static func contactChecks() {
        let m=patch()
        // Isolate the discrete response from an intentionally penetrating state.
        // The production acceptance guard separately rejects such an initial state.
        var floor=ClothSolver(m);floor.parameters.collisionSafety=false;floor.parameters.gravity = .zero;floor.parameters.selfContact=false;floor.floor=0
        floor.positions=m.initial.map{V3($0.x,-0.001,$0.y)}
        expect(floor.advance(),"Floor contact advances")
        expect(floor.positions.allSatisfy{$0.y>=floor.parameters.thickness/2-1e-8},"Floor thickness")
        func friction(_ mu:Double)->Double {
            var s=ClothSolver(m);s.floor=0;s.parameters.selfContact=false;s.parameters.friction=mu;s.parameters.damping=0
            s.positions=m.initial.map{V3($0.x,0.00025,$0.y)};s.velocities=s.velocities.map{_ in V3(0.1,0,0)}
            expect(s.advance(),"Friction step");return s.velocities.map{$0.x}.reduce(0,+)/4
        }
        let free=friction(0),drag=friction(0.4)
        expect(drag<free && drag >= -1e-8,"Coulomb friction dissipates tangential motion without reversal")
        expect(free-drag<=0.4*9.81/60+1e-6,"Friction impulse bounded by mu normal impulse")
        let rest=[SIMD2<Double>(0,0),SIMD2(0.1,0),SIMD2(0,0.1),SIMD2(0.2,0),SIMD2(0.3,0),SIMD2(0.2,0.1)]
        let p=[V3(0,0,0),V3(0.1,0,0),V3(0,0.1,0),V3(0.02,0.02,0.0001),V3(0.03,0.02,0.01),V3(0.02,0.03,0.01)]
        let mesh=ClothMesh(rest:rest,positions:p,indices:[[0,1,2],[3,4,5]])
        var selfContact=ClothSolver(mesh);selfContact.pins=[0:p[0],1:p[1],2:p[2]]
        for _ in 0..<4 {selfContact.selfContacts(old:p,weights:selfContact.weights)}
        expect(selfContact.positions[3].z>=0.00049,"Vertex-face self-contact thickness")
        let edgeP=[V3(-0.05,0,0),V3(0.05,0,0),V3(0,-0.04,-0.03),V3(0,-0.05,0),V3(0,0.05,0),V3(0.04,0,0.03)]
        let edgeMesh=ClothMesh(rest:rest,positions:edgeP,indices:[[0,1,2],[3,4,5]])
        var edge=ClothSolver(edgeMesh)
        for _ in 0..<8 {edge.selfContacts(old:edgeP,weights:edge.weights)}
        let (s,t)=ClothContact.closestSegments(edge.positions[0],edge.positions[1],edge.positions[3],edge.positions[4])
        let onA=edge.positions[0]*(1-s)+edge.positions[1]*s
        let onB=edge.positions[3]*(1-t)+edge.positions[4]*t
        expect(simd_length(onA-onB)>0.00048,"Edge-edge self-contact thickness")
        // Deliberately crossed the whole shell in one step: discrete proximity cannot detect it.
        var tunnel=ClothSolver(mesh);tunnel.positions[3].z = -0.01
        let crossed=tunnel.positions[3];tunnel.selfContacts(old:p,weights:tunnel.weights)
        expect(tunnel.positions[3]==crossed,"Known discrete VF tunnelling gap is exposed")
        var bad=ClothSolver(m);bad.velocities[0]=V3(1000,0,0)
        let saved=bad.positions;expect(!bad.advance() && bad.error != nil && bad.positions==saved,"Unsafe frame rolls back")
    }
}
