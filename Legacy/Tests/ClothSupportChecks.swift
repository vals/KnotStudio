import Foundation
import simd

@main struct ClothSupportChecks {
    static var count=0
    static func check(_ ok:Bool,_ message:String) {count+=1;if !ok {fputs("FAIL: \(message)\n",stderr);exit(1)}}
    static let shape=ClothCapsule(a:V3(-0.1,0,0),b:V3(0.1,0,0),radius:0.035)
    static func points(_ height:Double)->[V3] {[V3(-0.16,height,-0.12),V3(0.16,height,-0.12),V3(0,height,0.16)]}
    static func mesh(_ p:[V3])->ClothMesh {ClothMesh(rest:p.map{SIMD2($0.x,$0.z)},positions:p,indices:[[0,1,2]])}
    static func sweep(_ m:ClothMesh,_ a:[V3],_ b:[V3])->String? {
        var budget=200_000
        return ClothCollision.swept(m,a,b,capsules:[shape],floor:nil,thickness:0.0005,budget:&budget)
    }
    static func main() {
        let penetrating=points(0.02),m=mesh(penetrating)
        check(penetrating.allSatisfy{p in let (_,t)=ClothContact.closestSegments(p,p,shape.a,shape.b);return simd_distance(p,shape.a+t*(shape.b-shape.a))>shape.radius+0.00025},"All vertices clear despite penetrating face")
        let closest=ClothSupportContact.closest(penetrating,shape)
        check(abs(closest.distance-0.02)<1e-12,"Interior distance includes the finite face")
        check(abs(closest.bary.x+closest.bary.y+closest.bary.z-1)<1e-12 && closest.bary.min()>=0,"Closest point has valid barycentric coordinates")
        check(sweep(m,penetrating,penetrating) != nil,"Static face penetration rejected with clear vertices")
        var invalid=ClothSolver(m);invalid.capsules=[shape]
        check(!invalid.advance() && invalid.time==0 && !invalid.stateValid,"Invalid face contact blocks initial state")
        let thin=points(0.0351)
        check(sweep(mesh(thin),thin,thin) != nil,"Face above support but below half-thickness is rejected")
        let above=points(0.06),below=points(-0.06),valid=mesh(above)
        check(sweep(valid,above,above)==nil && sweep(valid,below,below)==nil,"Both endpoints of tunnelling case clear")
        check(sweep(valid,above,below) != nil,"Swept face tunnelling rejected even though every vertex path clears")
        let touching=points(0.03525),slide=touching.map{$0+V3(0.001,0,0)}
        check(sweep(mesh(touching),touching,slide)==nil,"Tangential whole-face motion at thickness remains accepted")
        // Actual nearly tangential impact from the support-strip regression.
        // A speed-only distance advance exhausted 64 iterations on this clear
        // path; interval plane certificates must accept it without a wider gap.
        let a=[V3(-0.019800835115343002,0.1789726024290839,0.03187477209107767),V3(-0.020458913513247034,0.1728687864370272,0.03846710091171474),V3(-0.010635704227877279,0.17329544462533053,0.039323014115589465)]
        let b=[V3(-0.019846218390975303,0.17877273477653446,0.032186752713027816),V3(-0.020478487158128455,0.1725446640733663,0.03863758208067304),V3(-0.01064309603209454,0.17286275002149246,0.03941462379810079)]
        let stripSupport=ClothCapsule(a:V3(-0.065,0.14,0),b:V3(0.065,0.14,0),radius:0.05)
        var intervalBudget=200_000
        check(ClothSupportContact.swept(a,b,stripSupport,separation:0.0002475,budget:&intervalBudget,cancelled:{false})==nil,"Bounded interval certificates accept near-tangential strip impact")
        var scripted=ClothSolver(valid);scripted.capsules=[shape]
        let saved=scripted.positions
        check(!scripted.advance(pinTargets:{_ in Dictionary(uniqueKeysWithValues:below.enumerated().map{($0.offset,$0.element)})}),"Scripted face crossing rejected")
        check(scripted.positions==saved && scripted.time==0 && scripted.pins.isEmpty,"Rejected face sweep rolls back atomically")
        let sphere=ClothCapsule(a:.zero,b:.zero,radius:0.035)
        check(abs(ClothSupportContact.closest(above,sphere).distance-0.06)<1e-12,"Degenerate capsule axis gives sphere-face distance")
        let crossing=[V3(-0.01,-0.05,-0.05),V3(-0.01,0.05,-0.05),V3(-0.01,0,0.05)]
        check(ClothSupportContact.closest(crossing,shape).distance<1e-12,"Axis piercing face yields zero distance")
        var budget=0
        check(ClothSupportContact.swept(above,above,shape,separation:0.0002475,budget:&budget,cancelled:{false}) != nil,"Support sweep budget exhaustion rejects")
        budget=200_000
        check(ClothSupportContact.swept(above,above,shape,separation:0.0002475,budget:&budget,cancelled:{true})==ClothCollision.cancellationReason,"Support sweep remains cancellable")
        var dynamic=ClothSolver(mesh(points(0.04)));dynamic.capsules=[shape]
        dynamic.parameters.gravity=V3(0,-50,0);dynamic.parameters.substeps=1
        dynamic.parameters.warp=0;dynamic.parameters.weft=0;dynamic.parameters.shear=0;dynamic.parameters.bending=0
        let initial=dynamic.positions
        check(dynamic.advance(),"Face response accepts real downward movement")
        check(dynamic.positions != initial && dynamic.time>0 && dynamic.snapshot().diagnostics.contacts>0,"Contact response moves geometry without freezing")
        let gap=ClothSupportContact.closest(dynamic.positions,shape).distance-shape.radius-0.00025
        check(gap >= -0.0000025,"Face response reaches existing shell acceptance tolerance")
        print("Response face gap: \(gap) m, time \(dynamic.time), retries \(dynamic.retries)")
        print("PASS: \(count) finite-face support response and swept checks")
    }
}
