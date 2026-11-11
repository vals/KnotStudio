import Foundation
import simd

/// Saved-instant audit, independent of the solver's acceptance decisions.
@main struct ClothWrapAudit {
    static func main() throws {
        var reports:[[String:Any]]=[]
        for name in CommandLine.arguments.dropFirst() {
            let data=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:name))) as! [String:Any]
            let p=(data["positions_m"] as! [[Double]]).map{V3($0[0],$0[1],$0[2])}
            let rest=(data["rest_m"] as! [[Double]]).map{SIMD2($0[0],$0[1])}
            let mesh=ClothMesh(rest:rest,positions:p,indices:data["triangles"] as! [[Int]])
            let intersections=ClothCollision.audit(mesh,p)
            var minimum=Double.infinity,principalMin=Double.infinity,principalMax=0.0
            // Both boxes expand by 15 mm. A finite result below 30 mm is
            // therefore a global nonlocal minimum, not just a narrow-phase sample.
            for pair in ClothCollision.pairs(mesh,p,padding:0.015).values {
                let a=mesh.triangles[pair.a].ids,b=mesh.triangles[pair.b].ids
                if ClothCollision.distance(a.map{V3(rest[$0].x,rest[$0].y,0)},b.map{V3(rest[$0].x,rest[$0].y,0)})<0.0005 {continue}
                minimum=min(minimum,ClothCollision.distance(a.map{p[$0]},b.map{p[$0]}))
            }
            precondition(minimum<0.03,"Search radius insufficient for global minimum")
            for t in mesh.triangles {
                let (u,v)=t.frame(p),a=simd_dot(u,u),b=simd_dot(u,v),c=simd_dot(v,v)
                let delta=sqrt((a-c)*(a-c)+4*b*b)
                principalMin=min(principalMin,sqrt(max(0,(a+c-delta)/2)))
                principalMax=max(principalMax,sqrt((a+c+delta)/2))
            }
            precondition(intersections.intersections.isEmpty && minimum>=0.000495,"Saved state failed native safety audit")
            reports.append(["file":URL(fileURLWithPath:name).lastPathComponent,"minimum_nonlocal_separation_m":minimum,"principal_stretch_min":principalMin,"principal_stretch_max":principalMax,"nonshared_intersections":intersections.intersections.count])
        }
        print(String(data:try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
