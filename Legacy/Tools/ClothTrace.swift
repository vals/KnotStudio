import Foundation
import simd
@main struct ClothTrace {
    static func main() {
        let e=ClothExperiment.make(.fourInHand,refineSeed:false,prepareSeed:false);var s=e.solver(),count=0
        let thickness=s.parameters.thickness
        s.parameters.collisionSafety=false
        s.parameters.projectionFraction=0
        s.trace={stage,p in
            guard count<22 else {return};count+=1
            let audit=ClothCollision.audit(e.mesh,p)
            var far=0,excluded=0,minFeature=Double.infinity,maxFeature=0.0
            for pair in audit.intersections {
                let a=e.mesh.triangles[pair.a].ids,b=e.mesh.triangles[pair.b].ids
                let d=ClothCollision.featureDistance(a.map{p[$0]},b.map{p[$0]})
                minFeature=min(minFeature,d);maxFeature=max(maxFeature,d)
                if d>thickness {far+=1}
                if a.contains(where:{i in b.contains(where:{e.mesh.neighbours[i].contains($0)})}) {excluded+=1}
            }
            print("\(count) \(stage): crossings=\(audit.intersections.count) far_from_endpoint_contacts=\(far) neighbour_related=\(excluded) feature_gap_m=\(minFeature)...\(maxFeature)");fflush(stdout)
        }
        _=s.advance()
    }
}
