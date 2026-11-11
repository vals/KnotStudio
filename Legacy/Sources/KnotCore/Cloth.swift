import Foundation
import simd

/// All mechanics use metres, seconds and kilograms. The chart is physical, not UV.
struct ClothTriangle {
    let ids:[Int]
    let u:[Double], v:[Double]
    let area:Double
    init(_ ids:[Int],rest:[SIMD2<Double>]) {
        self.ids=ids
        let a=rest[ids[1]]-rest[ids[0]], b=rest[ids[2]]-rest[ids[0]]
        let d=a.x*b.y-b.x*a.y
        precondition(abs(d)>1e-16,"Degenerate rest triangle")
        area=abs(d)*0.5
        u=[(a.y-b.y)/d,b.y/d,-a.y/d]
        v=[(b.x-a.x)/d,-b.x/d,a.x/d]
    }
    func frame(_ p:[V3])->(V3,V3) {
        (p[ids[0]]*u[0]+p[ids[1]]*u[1]+p[ids[2]]*u[2],p[ids[0]]*v[0]+p[ids[1]]*v[1]+p[ids[2]]*v[2])
    }
    /// 0=weft, 1=warp, 2=normalized shear. Values/gradients include sqrt(area).
    func constraint(_ mode:Int,_ p:[V3])->(Double,[V3]) {
        let (fu,fv)=frame(p), lu=max(1e-12,simd_length(fu)), lv=max(1e-12,simd_length(fv)), w=sqrt(area)
        if mode==0 { return ((lu-1)*w,u.map { fu*($0*w/lu) }) }
        if mode==1 { return ((lv-1)*w,v.map { fv*($0*w/lv) }) }
        let c=simd_dot(fu,fv)/(lu*lv), gu=(fv/lv-c*fu/lu)/lu, gv=(fu/lu-c*fv/lv)/lv
        return (c*w,(0..<3).map { (gu*u[$0]+gv*v[$0])*w })
    }
}

struct ClothEdge:Hashable {
    let a:Int,b:Int
    init(_ i:Int,_ j:Int) { a=min(i,j);b=max(i,j) }
}
struct ClothHinge {
    /// Shared edge a->b; opposite vertices c,d. Consistent triangle normals.
    let ids:[Int]
    let weight:Double
    func constraint(_ p:[V3])->(Double,[V3]) {
        let a=p[ids[0]],b=p[ids[1]],c=p[ids[2]],d=p[ids[3]], e=b-a
        let m1=simd_cross(e,c-a),m2=simd_cross(d-a,e)
        let le=simd_length(e),l1=simd_length(m1),l2=simd_length(m2)
        guard min(le,min(l1,l2))>1e-14 else { return (0,[V3](repeating:.zero,count:4)) }
        let h=e/le,n1=m1/l1,n2=m2/l2,x=simd_dot(n1,n2),y=simd_dot(h,simd_cross(n1,n2)),den=max(1e-20,x*x+y*y)
        let an1=(x*simd_cross(n2,h)-y*n2)/den,an2=(x*simd_cross(h,n1)-y*n1)/den,ah=x*simd_cross(n1,n2)/den
        let gm1=(an1-n1*simd_dot(an1,n1))/l1,gm2=(an2-n2*simd_dot(an2,n2))/l2
        let ge=(ah-h*simd_dot(ah,h))/le+simd_cross(c-a,gm1)+simd_cross(gm2,d-a)
        let gc=simd_cross(gm1,e),gd=simd_cross(e,gm2)
        return (atan2(y,x)*weight,[-ge-gc-gd,ge,gc,gd].map{$0*weight})
    }
}

struct ClothMesh {
    let rest:[SIMD2<Double>]
    let initial:[V3]
    let triangles:[ClothTriangle]
    let edges:[ClothEdge]
    let hinges:[ClothHinge]
    let masses:[Double]
    let neighbours:[Set<Int>]
    let localScale:[Double]
    init(rest:[SIMD2<Double>],positions:[V3],indices:[[Int]],density:Double=0.30) {
        precondition(rest.count==positions.count && density>0)
        self.rest=rest;initial=positions
        let triangles=indices.map{ClothTriangle($0,rest:rest)}
        self.triangles=triangles
        var mass=[Double](repeating:0,count:rest.count), near=[Set<Int>](repeating:[],count:rest.count)
        var sharing:[ClothEdge:[(Int,Int)]]=[:]
        for (ti,t) in triangles.enumerated() {
            for i in t.ids { mass[i]+=t.area*density/3;near[i].formUnion(t.ids) }
            for j in 0..<3 { sharing[ClothEdge(t.ids[j],t.ids[(j+1)%3]),default:[]].append((ti,t.ids[(j+2)%3])) }
        }
        edges=sharing.keys.sorted { $0.a==$1.a ? $0.b<$1.b : $0.a<$1.a }
        hinges=edges.compactMap { e in
            let t=sharing[e]!
            guard t.count==2 else {return nil}
            let len2=simd_length_squared(rest[e.b]-rest[e.a])
            return ClothHinge(ids:[e.a,e.b,t[0].1,t[1].1],weight:sqrt(3*len2/(triangles[t[0].0].area+triangles[t[1].0].area)))
        }
        var scale=[Double](repeating:.infinity,count:rest.count)
        for e in edges {let length=simd_length(rest[e.b]-rest[e.a]);scale[e.a]=min(scale[e.a],length);scale[e.b]=min(scale[e.b],length)}
        masses=mass;neighbours=near;localScale=scale
    }
}

struct ClothParameters {
    var warp=1800.0, weft=1200.0, shear=600.0 // N/m
    var bending=0.00002 // N m
    var gravity=V3(0,-9.81,0)
    var damping=0.8 // 1/s; numerical/material dissipation, not friction
    var thickness=0.0005 // separation between cloth mid-surfaces, metres
    var friction=0.35 // Coulomb coefficient, external contact only
    var substeps=6, iterations=8
    var selfContact=true
    var collisionSafety=true
    var maxCollisionRefinements=3
    var maxCollisionEvaluations=200_000
    var projectionFraction=0.25 // nonlinear XPBD trust region, relative to local rest edge
}
struct ClothCapsule { let a:V3,b:V3,radius:Double }
struct ClothDiagnostics {
    var warpMin=1.0,warpMax=1.0,weftMin=1.0,weftMax=1.0,shearMax=0.0,strainRMS=0.0
    var contacts=0,maxSpeed=0.0,minExternalGap=Double.infinity
}
struct ClothSnapshot {
    let positions:[V3]
    let pins:[Int:V3]
    let time:Double
    let diagnostics:ClothDiagnostics
    let error:String?
    let collisionStatus:String
    let stateValid:Bool
    let retries:Int
    let collisionEvaluations:Int
}

/// Rest-space membership and world pose of one grasp, independent of notation.
struct ClothGrasp {
    let vertices:[Int]
    let local:[V3]
    var position:V3
    var orientation=simd_quatd(angle:0,axis:V3(0,1,0))
    var held=true
    init(vertices:[Int],positions:[V3]) {
        self.vertices=vertices
        let center=vertices.map{positions[$0]}.reduce(.zero,+)/Double(vertices.count)
        position=center;local=vertices.map{positions[$0]-center}
    }
    var targets:[Int:V3] { held ? Dictionary(uniqueKeysWithValues:zip(vertices,local.map{position+orientation.act($0)})) : [:] }
}

struct ClothSolver {
    let mesh:ClothMesh
    var parameters=ClothParameters()
    var positions:[V3],velocities:[V3]
    var pins:[Int:V3]=[:]
    var capsules:[ClothCapsule]=[]
    var floor:Double?=nil
    private(set) var time=0.0
    private(set) var error:String?=nil
    private var contactCount=0
    private(set) var collisionStatus="Initial motion has not been checked"
    private(set) var stateValid=false
    private(set) var retries=0
    private(set) var collisionEvaluations=0
    private(set) var attemptFailures:[String]=[]
    private var cancelledThisFrame=false
    /// Optional diagnostic observer; never changes or accepts solver state.
    var trace:((String,[V3])->Void)?=nil
    init(_ mesh:ClothMesh) { self.mesh=mesh;positions=mesh.initial;velocities=[V3](repeating:.zero,count:mesh.initial.count) }
    mutating func reset() { positions=mesh.initial;velocities=[V3](repeating:.zero,count:positions.count);time=0;error=nil;contactCount=0;stateValid=false;collisionStatus="Initial motion has not been checked";retries=0;collisionEvaluations=0;attemptFailures=[];cancelledThisFrame=false }
    var weights:[Double] { mesh.masses.enumerated().map{pins[$0.offset]==nil ? 1/max(1e-12,$0.element):0} }
    mutating func advance(_ dt:Double=1.0/60,pinTargets:((Double)->[Int:V3])?=nil,cancelled:()->Bool={false})->Bool {
        guard error==nil,dt>0,dt<=1.0/30,parameters.substeps>0,parameters.iterations>0 else {return false}
        let savedP=positions,savedV=velocities,savedTime=time,savedContacts=contactCount,savedPins=pins
        var budget=parameters.maxCollisionEvaluations
        retries=0;collisionEvaluations=0;attemptFailures=[];cancelledThisFrame=false
        if !validPositions() {stateValid=false;collisionStatus="Invalid starting coordinates";error="No step taken: invalid starting coordinates.";return false}
        if parameters.collisionSafety {
            let audit=ClothCollision.audit(mesh,positions,cancelled:cancelled)
            if audit.interrupted {collisionStatus="Paused during initial collision audit";error=nil;return false}
            if !audit.intersections.isEmpty {
                stateValid=false;collisionStatus="Invalid starting mesh: \(audit.intersections.count) intersecting pairs"
                error="No step taken. \(collisionStatus). Reset or choose a valid experiment.";return false
            }
            let clearance=ClothCollision.clearance(mesh,positions,thickness:parameters.thickness,cancelled:cancelled)
            if clearance.interrupted {collisionStatus="Paused during initial clearance audit";error=nil;return false}
            if clearance.violations>0 {
                stateValid=false;collisionStatus="Invalid starting clearance: \(clearance.violations) nonlocal pairs below cloth thickness"
                error=String(format:"No step taken. Minimum separation %.3f mm; required %.3f mm.",clearance.minimum*1000,parameters.thickness*990);return false
            }
            if let issue=ClothCollision.swept(mesh,positions,positions,capsules:capsules,floor:floor,thickness:parameters.thickness,budget:&budget,cancelled:cancelled) {
                if issue==ClothCollision.cancellationReason {collisionStatus="Paused during initial swept audit";error=nil;return false}
                stateValid=false;collisionStatus="Starting clearance check failed"
                error="No step taken: \(issue).";collisionEvaluations=parameters.maxCollisionEvaluations-budget;return false
            }
            stateValid=true
        }
        let attempts=parameters.collisionSafety ? max(0,min(5,parameters.maxCollisionRefinements)):0
        var failure="unresolved step"
        for refinement in 0...attempts {
            positions=savedP;velocities=savedV;time=savedTime;pins=savedPins;error=nil;retries=refinement
            if attempt(dt,substeps:parameters.substeps*(1<<refinement),budget:&budget,pinTargets:pinTargets,cancelled:cancelled) {
                collisionEvaluations=parameters.maxCollisionEvaluations-budget
                collisionStatus=parameters.collisionSafety ? "Accepted: swept checks passed (\(parameters.substeps*(1<<refinement)) substeps)":"Collision acceptance disabled for diagnostic reproduction"
                stateValid=parameters.collisionSafety;return true
            }
            failure=error ?? failure
            attemptFailures.append(failure)
            if cancelledThisFrame || cancelled() {break}
            if budget<=0 {break}
        }
        positions=savedP;velocities=savedV;time=savedTime;contactCount=savedContacts;pins=savedPins
        collisionEvaluations=parameters.maxCollisionEvaluations-budget
        if cancelledThisFrame || cancelled() {collisionStatus="Paused: in-flight frame discarded; last checked state retained";error=nil;return false}
        collisionStatus=stateValid ? "Rejected: last valid state retained":"Rejected: no validated state"
        error="\(failure) Last state retained; simulated time did not advance. Reset to recover."
        return false
    }
    private mutating func attempt(_ dt:Double,substeps:Int,budget:inout Int,pinTargets:((Double)->[Int:V3])?,cancelled:()->Bool)->Bool {
        let savedP=positions,savedV=velocities,savedTime=time,h=dt/Double(substeps)
        contactCount=0
        trace?("initial",positions)
        for _ in 0..<substeps {
            let old=positions
            if let pinTargets=pinTargets {pins=pinTargets(time+h)}
            let w=weights
            let planes=parameters.selfContact && parameters.collisionSafety ? ClothCollision.contactPlanes(mesh,old,thickness:parameters.thickness,cancelled:cancelled):(planes:[],interrupted:false)
            if planes.interrupted {cancelledThisFrame=true;return reject(savedP,savedV,savedTime,"paused during contact preparation")}
            for i in positions.indices {
                if let target=pins[i] { positions[i]=target;velocities[i] = .zero }
                else { velocities[i]=velocities[i]*exp(-parameters.damping*h)+parameters.gravity*h;positions[i]+=velocities[i]*h }
            }
            if !validPositions() {return reject(savedP,savedV,savedTime)}
            trace?("prediction",positions)
            var lambda=[Double](repeating:0,count:mesh.triangles.count*3+mesh.hinges.count)
            for _ in 0..<parameters.iterations {
                if cancelled() {cancelledThisFrame=true;return reject(savedP,savedV,savedTime,"paused by user")}
                for (ti,t) in mesh.triangles.enumerated() { for mode in 0..<3 {
                    let stiffness=[parameters.weft,parameters.warp,parameters.shear][mode]
                    guard stiffness>0 else {continue}
                    let (c,g)=t.constraint(mode,positions)
                    project(t.ids,c,g,1/stiffness/(h*h),&lambda[ti*3+mode],w)
                }}
                trace?("membrane",positions)
                if parameters.bending>0 { for (hi,hinge) in mesh.hinges.enumerated() {
                    let (c,g)=hinge.constraint(positions)
                    project(hinge.ids,c,g,1/parameters.bending/(h*h),&lambda[mesh.triangles.count*3+hi],w)
                }}
                trace?("bending",positions)
                if !validPositions() {return reject(savedP,savedV,savedTime)}
                externalContacts(old:old,weights:w)
                trace?("external",positions)
                if parameters.selfContact { selfContacts(old:old,weights:w) }
                for plane in planes.planes {
                    var motion=V3.zero
                    for j in plane.ids.indices {motion+=(positions[plane.ids[j]]-old[plane.ids[j]])*plane.coefficients[j]}
                    let c=plane.distance-parameters.thickness+simd_dot(plane.normal,motion)
                    if c<0 {
                        var lambda=0.0
                        project(plane.ids,c,plane.coefficients.map{plane.normal*$0},0,&lambda,w);contactCount+=1
                    }
                }
                trace?("self-contact",positions)
            }
            for i in positions.indices { velocities[i]=pins[i]==nil ? (positions[i]-old[i])/h:.zero }
            if positions.contains(where:{ !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite || simd_length($0)>10 }) || velocities.contains(where:{ !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite || simd_length($0)>30 }) {
                let speed=velocities.map{simd_length($0)}.max() ?? 0
                return reject(savedP,savedV,savedTime,String(format:"peak speed %.1f m/s",speed))
            }
            // This path contains integration, prescribed grasp motion and every
            // material/contact correction in the net proposed substep.
            if parameters.collisionSafety,let issue=ClothCollision.swept(mesh,old,positions,capsules:capsules,floor:floor,thickness:parameters.thickness,budget:&budget,cancelled:cancelled) {
                if issue==ClothCollision.cancellationReason {cancelledThisFrame=true}
                return reject(savedP,savedV,savedTime,issue)
            }
            if parameters.collisionSafety {
                let clearance=ClothCollision.clearance(mesh,positions,thickness:parameters.thickness,cancelled:cancelled)
                if clearance.interrupted {cancelledThisFrame=true;return reject(savedP,savedV,savedTime,"paused during clearance audit")}
                if clearance.violations>0 {return reject(savedP,savedV,savedTime,"\(clearance.violations) pairs violate thickness after projection")}
            }
            time+=h
        }
        return true
    }
    private func validPositions()->Bool {positions.allSatisfy{$0.x.isFinite && $0.y.isFinite && $0.z.isFinite && simd_length($0)<10}}
    private mutating func reject(_ p:[V3],_ v:[V3],_ t:Double,_ reason:String="invalid geometry")->Bool {
        positions=p;velocities=v;time=t;error="Step rolled back: \(reason).";return false
    }
    private mutating func project(_ ids:[Int],_ c:Double,_ gradients:[V3],_ alpha:Double,_ lambda:inout Double,_ w:[Double]) {
        var denom=alpha
        for j in ids.indices {denom+=w[ids[j]]*simd_length_squared(gradients[j])}
        guard denom>1e-20 else {return}
        var dl=(-c-alpha*lambda)/denom
        if alpha>0 && parameters.projectionFraction>0 {
            var fraction=1.0
            for j in ids.indices {
                let magnitude=simd_length(gradients[j]) * abs(w[ids[j]]*dl)
                if magnitude>0 {fraction=min(fraction,parameters.projectionFraction*mesh.localScale[ids[j]]/magnitude)}
            }
            dl*=fraction // multiplier and position receive exactly the same relaxation
        }
        lambda+=dl
        for j in ids.indices {positions[ids[j]]+=gradients[j]*(w[ids[j]]*dl)}
    }
    private mutating func externalContacts(old:[V3],weights:[Double]) {
        let skin=parameters.thickness*0.5
        for i in positions.indices where weights[i]>0 {
            for shape in capsules {
                let axis=shape.b-shape.a,t=max(0,min(1,simd_dot(positions[i]-shape.a,axis)/max(1e-20,simd_length_squared(axis))))
                let q=shape.a+axis*t,d=positions[i]-q,length=simd_length(d)
                let penetration=shape.radius+skin-length
                if penetration>0 { let n=length>1e-12 ? d/length:V3(0,1,0);applyExternal(i,n,penetration,old[i]);contactCount+=1 }
            }
            if let level=floor { let penetration=level+skin-positions[i].y
                if penetration>0 {applyExternal(i,V3(0,1,0),penetration,old[i]);contactCount+=1}
            }
        }
        // Face/edge contact distributes a correction through its barycentric
        // coordinates and inverse masses. Pins remain fixed.
        for triangle in mesh.triangles {
            let ids=triangle.ids
            for shape in capsules {
                let nearest=ClothSupportContact.closest(ids.map{positions[$0]},shape)
                // Aim 1% of half-thickness outside the nominal surface to leave
                // a finite-iteration margin. Acceptance thresholds stay unchanged.
                let penetration=shape.radius+skin*1.01-nearest.distance
                if penetration<=0 {continue}
                let previous=ClothSupportContact.closest(ids.map{old[$0]},shape)
                let normal=nearest.distance>1e-12 ? (nearest.cloth-nearest.axis)/nearest.distance:unit(previous.cloth-previous.axis)
                let bary=nearest.bary
                let denom=(0..<3).reduce(0.0){$0+weights[ids[$1]]*bary[$1]*bary[$1]}
                if denom<=1e-20 {continue}
                let motion=(0..<3).reduce(V3.zero){$0+(positions[ids[$1]]-old[ids[$1]])*bary[$1]}
                let tangent=motion-normal*simd_dot(motion,normal),length=simd_length(tangent)
                let friction=length>1e-12 ? tangent*min(1,parameters.friction*penetration/length):.zero
                for j in 0..<3 {positions[ids[j]]+=(normal*penetration-friction)*(weights[ids[j]]*bary[j]/denom)}
                contactCount+=1
            }
        }
    }
    private mutating func applyExternal(_ i:Int,_ n:V3,_ amount:Double,_ old:V3) {
        positions[i]+=n*amount
        let motion=positions[i]-old,tangent=motion-n*simd_dot(motion,n),length=simd_length(tangent)
        if length>1e-12 {positions[i]-=tangent*min(1,parameters.friction*amount/length)}
    }
    mutating func selfContacts(old:[V3],weights:[Double]) {
        let skin=parameters.thickness,cell=0.018
        var grid:[SIMD3<Int>:[Int]]=[:]
        for (ti,t) in mesh.triangles.enumerated() {
            for key in ClothContact.cells(t.ids.map{positions[$0]},padding:skin,size:cell) {grid[key,default:[]].append(ti)}
        }
        for i in positions.indices {
            let key=ClothContact.key(positions[i],size:cell)
            for ti in grid[key] ?? [] {
                let ids=mesh.triangles[ti].ids
                if ids.contains(i) {continue}
                let r=mesh.rest,ri=V3(r[i].x,r[i].y,0),rp=ids.map{V3(r[$0].x,r[$0].y,0)}
                if simd_length(ri-ClothContact.closestTriangle(ri,rp[0],rp[1],rp[2]).0)<skin {continue}
                let (q,bary)=ClothContact.closestTriangle(positions[i],positions[ids[0]],positions[ids[1]],positions[ids[2]])
                let delta=positions[i]-q,d=simd_length(delta)
                if d>=skin {continue}
                let previous=old[i]-old[ids[0]]*bary.x-old[ids[1]]*bary.y-old[ids[2]]*bary.z
                let fallback=simd_length(previous)>1e-12 ? unit(previous):unit(simd_cross(positions[ids[1]]-positions[ids[0]],positions[ids[2]]-positions[ids[0]]))
                var n=d>1e-12 ? delta/d:fallback
                if simd_dot(n,previous)<0 {n = -n}
                var l=0.0;project([i]+ids,simd_dot(delta,n)-skin,[n,-bary.x*n,-bary.y*n,-bary.z*n],0,&l,weights);contactCount+=1
            }
        }
        grid.removeAll(keepingCapacity:true)
        for (ei,e) in mesh.edges.enumerated() {
            for key in ClothContact.cells([positions[e.a],positions[e.b]],padding:skin,size:cell) {grid[key,default:[]].append(ei)}
        }
        var pairs=Set<ClothEdge>()
        for entries in grid.values { for a in entries { for b in entries where b>a {pairs.insert(ClothEdge(a,b))} } }
        for pair in pairs.sorted(by:{$0.a==$1.a ? $0.b<$1.b:$0.a<$1.a}) {
            let a=mesh.edges[pair.a],b=mesh.edges[pair.b]
            if a.a==b.a || a.a==b.b || a.b==b.a || a.b==b.b {continue}
            let rest=[a.a,a.b,b.a,b.b].map{V3(mesh.rest[$0].x,mesh.rest[$0].y,0)}
            let (rs,rt)=ClothContact.closestSegments(rest[0],rest[1],rest[2],rest[3])
            let ra=rest[0]+rs*(rest[1]-rest[0]),rb=rest[2]+rt*(rest[3]-rest[2])
            if simd_length(ra-rb)<skin {continue}
            let (s,t)=ClothContact.closestSegments(positions[a.a],positions[a.b],positions[b.a],positions[b.b])
            let coefficients=[1-s,s,-(1-t),-t],ids=[a.a,a.b,b.a,b.b]
            let delta=(0..<4).reduce(V3.zero){$0+positions[ids[$1]]*coefficients[$1]},d=simd_length(delta)
            if d>=skin {continue}
            let previous=(0..<4).reduce(V3.zero){$0+old[ids[$1]]*coefficients[$1]}
            let axis=unit(positions[a.b]-positions[a.a]),cross=simd_cross(axis,positions[b.b]-positions[b.a])
            let perpendicular=simd_cross(axis,abs(axis.y)<0.9 ? V3(0,1,0):V3(1,0,0))
            let fallback=simd_length(previous)>1e-12 ? unit(previous):unit(simd_length(cross)>1e-12 ? cross:perpendicular)
            var n=d>1e-12 ? delta/d:fallback
            if simd_dot(n,previous)<0 {n = -n}
            var l=0.0;project(ids,simd_dot(delta,n)-skin,coefficients.map{$0*n},0,&l,weights);contactCount+=1
        }
    }
    func snapshot()->ClothSnapshot {
        var result=ClothDiagnostics(),sum=0.0,area=0.0
        result.warpMin = .infinity;result.weftMin = .infinity;result.warpMax=0;result.weftMax=0
        for t in mesh.triangles {
            let (u,v)=t.frame(positions),lu=simd_length(u),lv=simd_length(v),shear=abs(simd_dot(u,v))/max(1e-20,lu*lv)
            result.weftMin=min(result.weftMin,lu);result.weftMax=max(result.weftMax,lu)
            result.warpMin=min(result.warpMin,lv);result.warpMax=max(result.warpMax,lv)
            result.shearMax=max(result.shearMax,asin(min(1,shear))*180 / .pi)
            sum+=t.area*((lu-1)*(lu-1)+(lv-1)*(lv-1)+shear*shear);area+=t.area
        }
        result.strainRMS=sqrt(sum/max(1e-20,area*3));result.contacts=contactCount
        result.maxSpeed=velocities.map{simd_length($0)}.max() ?? 0
        for p in positions {
            if let floor=floor {result.minExternalGap=min(result.minExternalGap,p.y-floor-parameters.thickness/2)}
            for c in capsules {
                let axis=c.b-c.a,t=max(0,min(1,simd_dot(p-c.a,axis)/max(1e-20,simd_length_squared(axis))))
                result.minExternalGap=min(result.minExternalGap,simd_length(p-c.a-axis*t)-c.radius-parameters.thickness/2)
            }
        }
        for triangle in mesh.triangles {for shape in capsules {
            result.minExternalGap=min(result.minExternalGap,ClothSupportContact.closest(triangle.ids.map{positions[$0]},shape).distance-shape.radius-parameters.thickness/2)
        }}
        let visiblePins=Dictionary(uniqueKeysWithValues:pins.keys.map{($0,positions[$0])})
        return ClothSnapshot(positions:positions,pins:visiblePins,time:time,diagnostics:result,error:error,collisionStatus:collisionStatus,stateValid:stateValid,retries:retries,collisionEvaluations:collisionEvaluations)
    }
}

enum ClothContact {
    static func key(_ p:V3,size:Double)->SIMD3<Int> {SIMD3(Int(floor(p.x/size)),Int(floor(p.y/size)),Int(floor(p.z/size)))}
    static func cells(_ points:[V3],padding:Double,size:Double)->[SIMD3<Int>] {
        var lo=points[0],hi=lo
        for p in points.dropFirst() {lo=simd_min(lo,p);hi=simd_max(hi,p)}
        let a=key(lo-V3(repeating:padding),size:size),b=key(hi+V3(repeating:padding),size:size)
        // Reject pathological broadphase expansion; the step guard catches bad motion.
        guard b.x-a.x<100,b.y-a.y<100,b.z-a.z<100 else {return []}
        var keys:[SIMD3<Int>]=[]
        for x in a.x...b.x {for y in a.y...b.y {for z in a.z...b.z {keys.append(SIMD3(x,y,z))}}}
        return keys
    }
    static func closestTriangle(_ p:V3,_ a:V3,_ b:V3,_ c:V3)->(V3,V3) {
        let ab=b-a,ac=c-a,ap=p-a,d1=simd_dot(ab,ap),d2=simd_dot(ac,ap)
        if d1<=0 && d2<=0 {return (a,V3(1,0,0))}
        let bp=p-b,d3=simd_dot(ab,bp),d4=simd_dot(ac,bp)
        if d3>=0 && d4<=d3 {return (b,V3(0,1,0))}
        let vc=d1*d4-d3*d2
        if vc<=0 && d1>=0 && d3<=0 {let v=d1/(d1-d3);return (a+v*ab,V3(1-v,v,0))}
        let cp=p-c,d5=simd_dot(ab,cp),d6=simd_dot(ac,cp)
        if d6>=0 && d5<=d6 {return (c,V3(0,0,1))}
        let vb=d5*d2-d1*d6
        if vb<=0 && d2>=0 && d6<=0 {let w=d2/(d2-d6);return (a+w*ac,V3(1-w,0,w))}
        let va=d3*d6-d5*d4
        if va<=0 && d4-d3>=0 && d5-d6>=0 {let w=(d4-d3)/(d4-d3+d5-d6);return (b+w*(c-b),V3(0,1-w,w))}
        let denom=va+vb+vc
        if abs(denom)<1e-30 {return (a,V3(1,0,0))}
        let v=vb/denom,w=vc/denom
        return (a+ab*v+ac*w,V3(1-v-w,v,w))
    }
    static func closestSegments(_ a:V3,_ b:V3,_ c:V3,_ d:V3)->(Double,Double) {
        let u=b-a,v=d-c,w=a-c,A=simd_dot(u,u),B=simd_dot(u,v),C=simd_dot(v,v),D=simd_dot(u,w),E=simd_dot(v,w)
        func clamp(_ x:Double)->Double {max(0,min(1,x))}
        if A<1e-20 {return (0,clamp(E/max(C,1e-20)))}
        if C<1e-20 {return (clamp(-D/A),0)}
        let den=A*C-B*B
        var s=den>1e-20 ? clamp((B*E-C*D)/den):0
        var t=(B*s+E)/C
        if t<0 {t=0;s=clamp(-D/A)} else if t>1 {t=1;s=clamp((B-D)/A)}
        return (s,t)
    }
}
