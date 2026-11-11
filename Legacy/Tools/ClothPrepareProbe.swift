import Foundation
@main struct ClothPrepareProbe {
    static func main() {
        let e=ClothExperiment.make(.fourInHand,prepareSeed:false);var solver=e.solver()
        let start=Date()
        for iteration in 0..<80 {
            let old=solver.positions,c=ClothCollision.clearance(e.mesh,old,thickness:solver.parameters.thickness)
            if iteration%5==0 || c.violations==0 {print("iteration=\(iteration) minimum=\(c.minimum) violations=\(c.violations) wall=\(Date().timeIntervalSince(start))");fflush(stdout)}
            if c.violations==0 {break}
            solver.selfContacts(old:old,weights:solver.weights)
            let proposed=solver.positions;var accepted=false
            for step in 0..<12 {
                let fraction=pow(0.5,Double(step))
                let candidate=old.indices.map{old[$0]+(proposed[$0]-old[$0])*fraction}
                var budget=200000
                if ClothCollision.swept(e.mesh,old,candidate,capsules:[],floor:nil,budget:&budget)==nil {solver.positions=candidate;accepted=true;break}
            }
            if !accepted {print("Preparation stalled; previous state retained");break}
        }
        let audit=ClothCollision.audit(e.mesh,solver.positions)
        print("Final intersections=\(audit.intersections.count)")
    }
}
