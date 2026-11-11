import Foundation
@main struct ClothSeedAudit {
    static func main() {
        for refine in [false,true] {
            let e=ClothExperiment.make(.fourInHand,refineSeed:refine,prepareSeed:false),audit=ClothCollision.audit(e.mesh,e.mesh.initial)
            print("refined=\(refine) vertices=\(e.mesh.initial.count) intersections=\(audit.intersections.count) pairs=\(audit.candidates)")
            let clearance=ClothCollision.clearance(e.mesh,e.mesh.initial,thickness:0.0005)
            print("minimum nonlocal separation m=\(clearance.minimum), thickness violations=\(clearance.violations)")
        }
    }
}
