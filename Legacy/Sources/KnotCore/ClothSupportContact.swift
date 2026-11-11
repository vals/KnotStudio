import Foundation
import simd

/// Finite triangle against a capsule axis. The closest feature can be a face,
/// edge, or vertex; checking cloth vertices alone is insufficient.
enum ClothSupportContact {
    struct Closest {
        let cloth:V3,axis:V3,bary:V3
        var distance:Double {simd_distance(cloth,axis)}
    }
    static func closest(_ p:[V3],_ shape:ClothCapsule)->Closest {
        let ab=p[1]-p[0],ac=p[2]-p[0],n=simd_cross(ab,ac),axis=shape.b-shape.a
        let denominator=simd_dot(n,axis)
        if abs(denominator)>1e-25 {
            let t=simd_dot(n,p[0]-shape.a)/denominator
            if t>=0 && t<=1 {
                let q=shape.a+t*axis,(point,bary)=ClothContact.closestTriangle(q,p[0],p[1],p[2])
                if simd_distance(point,q)<1e-12 {return Closest(cloth:point,axis:q,bary:bary)}
            }
        }
        let (first,bary)=ClothContact.closestTriangle(shape.a,p[0],p[1],p[2])
        var best=Closest(cloth:first,axis:shape.a,bary:bary)
        let (last,lastBary)=ClothContact.closestTriangle(shape.b,p[0],p[1],p[2])
        if simd_distance(last,shape.b)<best.distance {best=Closest(cloth:last,axis:shape.b,bary:lastBary)}
        for i in 0..<3 {
            let j=(i+1)%3,(s,t)=ClothContact.closestSegments(p[i],p[j],shape.a,shape.b)
            let point=p[i]+s*(p[j]-p[i]),q=shape.a+t*axis
            if simd_distance(point,q)<best.distance {
                var bary=V3.zero;bary[i]=1-s;bary[j]=s
                best=Closest(cloth:point,axis:q,bary:bary)
            }
        }
        return best
    }
    /// A capsule's support function gives a sufficient separating-plane test
    /// for the convex hull of all six endpoints of a moving triangle.
    static func planeClear(_ points:[V3],_ shape:ClothCapsule,_ normal:V3,_ separation:Double)->Bool {
        let length=simd_length(normal);if length<1e-14 {return false}
        let n=normal/length
        let support=max(simd_dot(shape.a,n),simd_dot(shape.b,n))+shape.radius+separation
        return points.allSatisfy{simd_dot($0,n)>support+1e-12}
    }
    static func swept(_ start:[V3],_ end:[V3],_ shape:ClothCapsule,separation:Double,budget:inout Int,cancelled:()->Bool)->String? {
        if cancelled() {return ClothCollision.cancellationReason}
        budget-=1;if budget<0 {return "collision work budget exhausted"}
        let first=closest(start,shape),last=closest(end,shape)
        if planeClear(start+end,shape,first.cloth-first.axis,separation) || planeClear(start+end,shape,last.cloth-last.axis,separation) {return nil}
        let delta=(0..<3).map{end[$0]-start[$0]},bound=delta.map{simd_length($0)}.max()!
        if min(first.distance,last.distance)<=shape.radius+separation {return "triangle interior support contact"}
        // Subdivide only unresolved time intervals. Each accepted interval is
        // covered by a fixed support plane or by the global Hausdorff speed
        // bound around its midpoint. Point samples alone never accept motion.
        var intervals:[(Double,Double)]=[(0,1)]
        for _ in 0..<64 {
            if cancelled() {return ClothCollision.cancellationReason}
            guard let (lo,hi)=intervals.popLast() else {return nil}
            budget-=1;if budget<0 {return "collision work budget exhausted"}
            let middle=(lo+hi)/2
            let a=(0..<3).map{start[$0]+lo*delta[$0]},b=(0..<3).map{start[$0]+hi*delta[$0]}
            let p=(0..<3).map{start[$0]+middle*delta[$0]},current=closest(p,shape)
            let gap=current.distance-shape.radius-separation
            if !gap.isFinite || gap<=0 {return "triangle interior support contact"}
            if planeClear(a+b,shape,current.cloth-current.axis,separation) || gap>bound*(hi-lo)/2+1e-12 {continue}
            if hi-lo<1e-8 {return "unresolved triangle-support sweep"}
            intervals.append((middle,hi));intervals.append((lo,middle))
        }
        return intervals.isEmpty ? nil:"triangle-support sweep iteration limit"
    }
}
