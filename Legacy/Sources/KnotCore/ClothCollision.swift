import Foundation
import simd

/// Finite triangle predicates in metres. No dependency on rendering or notation.
enum ClothCollision {
    static let epsilon=1e-10
    static let cancellationReason="paused during collision checks"
    struct Pair {let a:Int,b:Int}
    struct PairSearch {var values:[Pair]=[];var interrupted=false}
    struct ContactPlane {let ids:[Int],coefficients:[Double],normal:V3,distance:Double}
    struct Audit {
        var intersections:[Pair]=[]
        var candidates=0
        var interrupted=false
    }
    /// Swept AABBs, sweep-and-prune on x. Unlike the old hash this never silently
    /// drops oversized boxes. Topologically shared vertices are excluded here.
    static func pairs(_ mesh:ClothMesh,_ p:[V3],_ end:[V3]?=nil,padding:Double=0,cancelled:()->Bool={false})->PairSearch {
        var low=[V3](),high=[V3]()
        low.reserveCapacity(mesh.triangles.count);high.reserveCapacity(mesh.triangles.count)
        for t in mesh.triangles {
            if cancelled() {return PairSearch(interrupted:true)}
            var a=p[t.ids[0]],b=a
            for i in t.ids {a=simd_min(a,p[i]);b=simd_max(b,p[i]);if let end=end {a=simd_min(a,end[i]);b=simd_max(b,end[i])}}
            low.append(a-V3(repeating:padding));high.append(b+V3(repeating:padding))
        }
        let order=low.indices.sorted{low[$0].x==low[$1].x ? $0<$1:low[$0].x<low[$1].x}
        if cancelled() {return PairSearch(interrupted:true)}
        var result:[Pair]=[]
        for k in order.indices {
            if cancelled() {return PairSearch(interrupted:true)}
            let i=order[k]
            for l in k+1..<order.count {
                if (l-k)%128==0 && cancelled() {return PairSearch(interrupted:true)}
                let j=order[l]
                if low[j].x>high[i].x {break}
                if low[j].y>high[i].y || low[i].y>high[j].y || low[j].z>high[i].z || low[i].z>high[j].z {continue}
                if mesh.triangles[i].ids.contains(where:{mesh.triangles[j].ids.contains($0)}) {continue}
                result.append(Pair(a:min(i,j),b:max(i,j)))
            }
        }
        let sorted=result.sorted{$0.a==$1.a ? $0.b<$1.b:$0.a<$1.a}
        return cancelled() ? PairSearch(interrupted:true):PairSearch(values:sorted)
    }
    static func segmentTriangle(_ p:V3,_ q:V3,_ a:V3,_ b:V3,_ c:V3)->Bool {
        let n=simd_cross(b-a,c-a),len=simd_length(n)
        if len<1e-18 {return false}
        let unitN=n/len,dp=simd_dot(p-a,unitN),dq=simd_dot(q-a,unitN)
        if (dp>epsilon && dq>epsilon)||(dp < -epsilon && dq < -epsilon) {return false}
        let denominator=dp-dq
        if abs(denominator)<epsilon {return false} // coplanar handled separately
        let t=dp/denominator
        if t < -1e-9 || t > 1+1e-9 {return false}
        let r=p+(q-p)*t,v0=b-a,v1=c-a,v2=r-a
        let d00=simd_dot(v0,v0),d01=simd_dot(v0,v1),d11=simd_dot(v1,v1),d20=simd_dot(v2,v0),d21=simd_dot(v2,v1)
        let den=d00*d11-d01*d01
        if abs(den)<1e-30 {return false}
        let v=(d11*d20-d01*d21)/den,w=(d00*d21-d01*d20)/den
        return v >= -1e-8 && w >= -1e-8 && v+w<=1+1e-8
    }
    static func intersects(_ a:[V3],_ b:[V3])->Bool {
        for k in 0..<3 {
            if segmentTriangle(a[k],a[(k+1)%3],b[0],b[1],b[2]) || segmentTriangle(b[k],b[(k+1)%3],a[0],a[1],a[2]) {return true}
        }
        let n=simd_cross(a[1]-a[0],a[2]-a[0]),length=simd_length(n)
        if length<1e-18 {return false}
        if b.contains(where:{abs(simd_dot($0-a[0],n/length))>epsilon}) {return false}
        // Coplanar overlap, including an edge crossing without contained vertices.
        for p in a {if simd_length(ClothContact.closestTriangle(p,b[0],b[1],b[2]).0-p)<epsilon {return true}}
        for p in b {if simd_length(ClothContact.closestTriangle(p,a[0],a[1],a[2]).0-p)<epsilon {return true}}
        for i in 0..<3 {for j in 0..<3 {
            let (s,t)=ClothContact.closestSegments(a[i],a[(i+1)%3],b[j],b[(j+1)%3])
            let pa=a[i]+s*(a[(i+1)%3]-a[i]),pb=b[j]+t*(b[(j+1)%3]-b[j])
            if simd_length(pa-pb)<epsilon {return true}
        }}
        return false
    }
    static func featureDistance(_ a:[V3],_ b:[V3])->Double {
        var distance=Double.infinity
        for p in a {distance=min(distance,simd_length(p-ClothContact.closestTriangle(p,b[0],b[1],b[2]).0))}
        for p in b {distance=min(distance,simd_length(p-ClothContact.closestTriangle(p,a[0],a[1],a[2]).0))}
        for i in 0..<3 {for j in 0..<3 {
            let (s,t)=ClothContact.closestSegments(a[i],a[(i+1)%3],b[j],b[(j+1)%3])
            let pa=a[i]+s*(a[(i+1)%3]-a[i]),pb=b[j]+t*(b[(j+1)%3]-b[j])
            distance=min(distance,simd_length(pa-pb))
        }}
        return distance
    }
    static func distance(_ a:[V3],_ b:[V3])->Double {intersects(a,b) ? 0:featureDistance(a,b)}
    /// A fixed separating plane for the two swept convex hulls is sufficient to
    /// certify the whole path. This avoids exhausting advancement on tangential
    /// sliding at finite thickness, while retaining the conservative fallback.
    static func sweptPlane(_ a:[V3],_ b:[V3],_ da:[V3],_ db:[V3],separation:Double)->Bool {
        let ae=(0..<3).map{a[$0]+da[$0]},be=(0..<3).map{b[$0]+db[$0]}
        let aa=a+ae,bb=b+be
        var axes:[V3]=[]
        for triangle in [a,b,ae,be] {
            let n=simd_cross(triangle[1]-triangle[0],triangle[2]-triangle[0]);axes.append(n)
            for i in 0..<3 {axes.append(simd_cross(n,triangle[(i+1)%3]-triangle[i]))}
        }
        for axis in axes {
            let length=simd_length(axis);if length<1e-20 {continue}
            let n=axis/length,ap=aa.map{simd_dot($0,n)},bp=bb.map{simd_dot($0,n)}
            if ap.min()!-bp.max()!>separation+1e-12 || bp.min()!-ap.max()!>separation+1e-12 {return true}
        }
        return false
    }
    static func audit(_ mesh:ClothMesh,_ p:[V3],cancelled:()->Bool={false})->Audit {
        let candidates=pairs(mesh,p,padding:epsilon,cancelled:cancelled)
        var result=Audit();result.candidates=candidates.values.count
        if candidates.interrupted {result.interrupted=true;return result}
        for pair in candidates.values {
            if cancelled() {result.interrupted=true;return result}
            if intersects(mesh.triangles[pair.a].ids.map{p[$0]},mesh.triangles[pair.b].ids.map{p[$0]}) {result.intersections.append(pair)}
        }
        return result
    }
    /// Thickness applies to nonlocal material pairs. A flat-material proximity
    /// exclusion replaces the overly broad one-ring contact exclusion.
    static func clearance(_ mesh:ClothMesh,_ p:[V3],thickness:Double,cancelled:()->Bool={false})->(minimum:Double,violations:Int,interrupted:Bool) {
        var minimum=Double.infinity,violations=0
        let search=pairs(mesh,p,padding:thickness,cancelled:cancelled)
        if search.interrupted {return (minimum,violations,true)}
        for pair in search.values {
            if cancelled() {return (minimum,violations,true)}
            let ai=mesh.triangles[pair.a].ids,bi=mesh.triangles[pair.b].ids
            let a=ai.map{V3(mesh.rest[$0].x,mesh.rest[$0].y,0)},b=bi.map{V3(mesh.rest[$0].x,mesh.rest[$0].y,0)}
            if distance(a,b)<thickness {continue}
            let separation=distance(ai.map{p[$0]},bi.map{p[$0]})
            minimum=min(minimum,separation)
            if separation<thickness*0.99 {violations+=1}
        }
        return (minimum,violations,false)
    }
    /// Frictionless, old-side contact planes constrain closing displacement.
    /// They are a response model; the swept acceptance check is still mandatory.
    static func contactPlanes(_ mesh:ClothMesh,_ p:[V3],thickness:Double,cancelled:()->Bool={false})->(planes:[ContactPlane],interrupted:Bool) {
        var contacts:[ContactPlane]=[],vf=Set<SIMD2<Int>>(),ee=Set<ClothEdge>()
        let edges=Dictionary(uniqueKeysWithValues:mesh.edges.enumerated().map{($0.element,$0.offset)})
        let rest=mesh.rest.map{V3($0.x,$0.y,0)}
        let search=pairs(mesh,p,padding:thickness*1.5,cancelled:cancelled)
        if search.interrupted {return ([],true)}
        for pair in search.values {
            if cancelled() {return ([],true)}
            for (a,b) in [(pair.a,pair.b),(pair.b,pair.a)] {
                let triangle=mesh.triangles[b].ids
                for i in mesh.triangles[a].ids {
                    if !vf.insert(SIMD2(i,b)).inserted {continue}
                    if simd_length(rest[i]-ClothContact.closestTriangle(rest[i],rest[triangle[0]],rest[triangle[1]],rest[triangle[2]]).0)<thickness {continue}
                    let (q,bary)=ClothContact.closestTriangle(p[i],p[triangle[0]],p[triangle[1]],p[triangle[2]])
                    let delta=p[i]-q,d=simd_length(delta)
                    if d>1e-12 && d<thickness*1.5 {contacts.append(ContactPlane(ids:[i]+triangle,coefficients:[1,-bary.x,-bary.y,-bary.z],normal:delta/d,distance:d))}
                }
            }
            let a=mesh.triangles[pair.a].ids,b=mesh.triangles[pair.b].ids
            for i in 0..<3 {for j in 0..<3 {
                let first=ClothEdge(a[i],a[(i+1)%3]),second=ClothEdge(b[j],b[(j+1)%3])
                if !ee.insert(ClothEdge(edges[first]!,edges[second]!)).inserted {continue}
                let ids=[first.a,first.b,second.a,second.b]
                let (rs,rt)=ClothContact.closestSegments(rest[ids[0]],rest[ids[1]],rest[ids[2]],rest[ids[3]])
                let ra=rest[ids[0]]+rs*(rest[ids[1]]-rest[ids[0]]),rb=rest[ids[2]]+rt*(rest[ids[3]]-rest[ids[2]])
                if simd_length(ra-rb)<thickness {continue}
                let (s,t)=ClothContact.closestSegments(p[ids[0]],p[ids[1]],p[ids[2]],p[ids[3]])
                let coefficients=[1-s,s,-(1-t),-t]
                let delta=(0..<4).reduce(V3.zero){$0+p[ids[$1]]*coefficients[$1]},d=simd_length(delta)
                if d>1e-12 && d<thickness*1.5 {contacts.append(ContactPlane(ids:ids,coefficients:coefficients,normal:delta/d,distance:d))}
            }}
        }
        return (contacts,false)
    }

    /// Certifies a linear path with a Lipschitz distance bound. Failure includes
    /// unresolved/budget-limited paths; it never treats iteration exhaustion as safe.
    static func swept(_ mesh:ClothMesh,_ start:[V3],_ end:[V3],capsules:[ClothCapsule],floor:Double?,thickness:Double=0,budget:inout Int,cancelled:()->Bool={false})->String? {
        let guardDistance=1e-7 // numerical nonintersection guard; NOT cloth thickness
        for triangle in mesh.triangles {
            if cancelled() {return cancellationReason}
            let ids=triangle.ids,e=start[ids[1]]-start[ids[0]],f=start[ids[2]]-start[ids[0]]
            let de=end[ids[1]]-end[ids[0]]-e,df=end[ids[2]]-end[ids[0]]-f
            let n0=simd_cross(e,f),n1=simd_cross(de,f)+simd_cross(e,df),n2=simd_cross(de,df)
            let bound=simd_length(n1)+2*simd_length(n2),areaGuard=max(1e-16,triangle.area*1e-6)
            var t=0.0,certified=false
            for _ in 0..<64 {
                if cancelled() {return cancellationReason}
                budget-=1;if budget<0 {return "collision work budget exhausted"}
                let gap=simd_length(n0+n1*t+n2*t*t)-areaGuard
                if !gap.isFinite || gap<=0 {break}
                if bound<1e-20 {certified=true;break}
                let safe=0.9*gap/bound
                if safe>=1-t {certified=true;break}
                if safe<1e-8 {break};t+=safe
            }
            if !certified {return "triangle collapse or unresolved area during motion"}
        }
        let search=pairs(mesh,start,end,padding:max(guardDistance,thickness),cancelled:cancelled)
        if search.interrupted {return cancellationReason}
        for pair in search.values {
            if cancelled() {return cancellationReason}
            let a=mesh.triangles[pair.a].ids.map{start[$0]},b=mesh.triangles[pair.b].ids.map{start[$0]}
            let da=mesh.triangles[pair.a].ids.map{end[$0]-start[$0]},db=mesh.triangles[pair.b].ids.map{end[$0]-start[$0]}
            var separation=guardDistance
            if thickness>0 {
                let ar=mesh.triangles[pair.a].ids.map{V3(mesh.rest[$0].x,mesh.rest[$0].y,0)},br=mesh.triangles[pair.b].ids.map{V3(mesh.rest[$0].x,mesh.rest[$0].y,0)}
                if distance(ar,br)>=thickness {separation=max(guardDistance,thickness*0.99)}
            }
            budget-=1;if budget<0 {return "collision work budget exhausted"}
            if sweptPlane(a,b,da,db,separation:separation) {continue}
            // Remove common translation for a tighter, still conservative bound.
            let common=(da+db).reduce(.zero,+)/6
            let bound=(da.map{simd_length($0-common)}.max() ?? 0)+(db.map{simd_length($0-common)}.max() ?? 0)
            var t=0.0,certified=false
            for _ in 0..<64 {
                if cancelled() {return cancellationReason}
                budget-=1;if budget<0 {return "collision work budget exhausted"}
                let aa=(0..<3).map{a[$0]+da[$0]*t},bb=(0..<3).map{b[$0]+db[$0]*t}
                let gap=distance(aa,bb)-separation
                if !gap.isFinite || gap<=0 {break}
                if bound<1e-15 {certified=true;break}
                let safe=0.9*gap/bound
                if safe>=1-t {certified=true;break}
                if safe<1e-8 {break}
                t+=safe
            }
            if !certified {return "swept self-contact unresolved at triangles \(pair.a)/\(pair.b)"}
        }
        for (ti,triangle) in mesh.triangles.enumerated() {
            for shape in capsules {
                let a=triangle.ids.map{start[$0]},b=triangle.ids.map{end[$0]}
                if let issue=ClothSupportContact.swept(a,b,shape,separation:max(guardDistance,thickness*0.495),budget:&budget,cancelled:cancelled) {
                    if issue==cancellationReason {return issue}
                    return "\(issue) at triangle \(ti)"
                }
            }
        }
        for i in start.indices {
            if cancelled() {return cancellationReason}
            let solidGuard=max(guardDistance,thickness*0.495)
            if let floor=floor,min(start[i].y,end[i].y)<floor+solidGuard {return "floor crossing at vertex \(i)"}
            for c in capsules {
                budget-=1;if budget<0 {return "collision work budget exhausted"}
                let (s,t)=ClothContact.closestSegments(start[i],end[i],c.a,c.b)
                let p=start[i]+(end[i]-start[i])*s,q=c.a+(c.b-c.a)*t
                if simd_length(p-q)<c.radius+solidGuard {return "swept support contact at vertex \(i)"}
            }
        }
        return nil
    }
}
