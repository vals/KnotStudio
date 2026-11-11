import Foundation
import simd

/// One explicit manipulation script, not a notation parser or general planner.
struct ClothWrapSequence {
    static let columns=5,rows=65
    static let length=0.32,materialStart=0.30,anchor=0.04
    static let radius=0.035,guideRadius=0.03575,centerY=0.16,pitch=0.032
    static let settle=0.25,form=4.0,hold=0.5,slide=0.5,finalHold=0.25,slideDistance=0.005
    static var duration:Double {settle+form+hold+slide+finalHold}
    static func isComplete(_ time:Double)->Bool {time>=duration-1e-9}
    static var beta:Double {atan(pitch/(2 * .pi * guideRadius))}
    let fixed:ClothGrasp,active:ClothGrasp
    let activeLength:Double
    init(mesh:ClothMesh) {
        fixed=ClothGrasp(vertices:Array(0..<Self.columns*2),positions:mesh.initial)
        active=ClothGrasp(vertices:Array((Self.rows-2)*Self.columns..<Self.rows*Self.columns),positions:mesh.initial)
        activeLength=Self.length-Self.length/Double(Self.rows-1)/2-Self.anchor
    }
    static func smooth(_ x:Double)->Double {let t=max(0,min(1,x));return t*t*t*(10+t*(-15+6*t))}
    static func phase(_ time:Double)->String {
        if time<settle-1e-9 {return "Flat settle"}
        if time<settle+form-1e-9 {return "Form one wrap"}
        if time<settle+form+hold-1e-9 {return "Hold contact"}
        if time<settle+form+hold+slide-1e-9 {return "Slide 5 mm"}
        if time<duration-1e-9 {return "Final hold"}
        return "Complete"
    }
    func targets(at time:Double)->[Int:V3] {
        let theta=2 * Double.pi * Self.smooth((time-Self.settle)/Self.form)
        let shift=Self.slideDistance*Self.smooth((time-Self.settle-Self.form-Self.hold)/Self.slide)
        let b=Self.beta,r=Self.guideRadius
        let tangent=V3(sin(b),-cos(b)*sin(theta),cos(b)*cos(theta))
        let contact=V3(Self.pitch*theta/(2 * .pi),Self.centerY+r*cos(theta),r*sin(theta))
        let remaining=activeLength-r*theta/cos(b)
        var a=active,f=fixed
        a.position=contact+tangent*remaining+V3(shift,0,0)
        a.orientation=simd_quatd(angle:theta,axis:V3(1,0,0))
        f.position+=V3(shift,0,0)
        return f.targets.merging(a.targets){_,b in b}
    }
    static func experiment()->ClothExperiment {
        var rest:[SIMD2<Double>]=[],positions:[V3]=[],indices:[[Int]]=[]
        let across=V3(cos(beta),0,-sin(beta)),along=V3(sin(beta),0,cos(beta))
        for i in 0..<rows {
            let s=Double(i)/Double(rows-1)*length,width=TieBlank.width(at:(materialStart+s)*100)/100
            for j in 0..<columns {
                let u=(Double(j)/Double(columns-1)-0.5)*width
                rest.append(SIMD2(u,materialStart+s))
                positions.append(V3(0,centerY+guideRadius,0)+along*(s-anchor)-across*u)
            }
        }
        for i in 0..<rows-1 {for j in 0..<columns-1 {
            let a=i*columns+j,b=a+1,c=a+columns,d=c+1
            indices.append([a,b,c]);indices.append([b,d,c])
        }}
        let mesh=ClothMesh(rest:rest,positions:positions,indices:indices),plan=Self(mesh:mesh)
        let support=ClothCapsule(a:V3(-0.10,centerY,0),b:V3(0.10,centerY,0),radius:radius)
        return ClothExperiment(mesh:mesh,fixed:plan.fixed.targets,grasp:plan.active,capsules:[support],floor:-0.18,kind:.wrap)
    }
    struct Metrics {
        var nearContactVertices=0,nearContactTriangles=0
        var minimumTriangleSupportGap=Double.infinity
        var minimumSupportGap=Double.infinity
        var angularSpan=0.0,nearSupportArc=0.0,meanFreeX=0.0
    }
    static func metrics(_ solver:ClothSolver)->Metrics {
        var result=Metrics(),freeCount=0
        let half=solver.parameters.thickness/2
        for i in solver.positions.indices where solver.pins[i]==nil {
            let p=solver.positions[i],q=V3(max(-0.1,min(0.1,p.x)),centerY,0)
            let gap=simd_length(p-q)-radius-half
            result.minimumSupportGap=min(result.minimumSupportGap,gap)
            if gap<=0.00005 {result.nearContactVertices+=1}
            result.meanFreeX+=p.x;freeCount+=1
        }
        for triangle in solver.mesh.triangles {
            let gap=ClothSupportContact.closest(triangle.ids.map{solver.positions[$0]},solver.capsules[0]).distance-radius-half
            result.minimumTriangleSupportGap=min(result.minimumTriangleSupportGap,gap)
            if gap<=0.00005 && triangle.ids.contains(where:{solver.pins[$0]==nil}) {result.nearContactTriangles+=1}
        }
        result.meanFreeX/=Double(max(1,freeCount))
        var previous=0.0,angles:[Double]=[],near:[Double]=[]
        for row in 0..<rows {
            let p=solver.positions[row*columns+columns/2]
            var angle=atan2(p.z,p.y-centerY)
            if row>0 {while angle-previous > .pi {angle-=2 * .pi};while angle-previous < -.pi {angle+=2 * .pi}}
            previous=angle;angles.append(angle)
            let radial=hypot(p.y-centerY,p.z)
            if radial<radius+0.003 && abs(p.x)<0.1 {near.append(angle)}
        }
        result.angularSpan=(angles.max()!-angles.min()!)*180 / .pi
        if let first=near.min(),let last=near.max() {result.nearSupportArc=(last-first)*180 / .pi}
        return result
    }
}
