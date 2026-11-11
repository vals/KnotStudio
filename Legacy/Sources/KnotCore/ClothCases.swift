import Foundation
import simd

enum ClothCase:String,CaseIterable,Identifiable {
    case strip="Strip over support",fold="Fold onto held cloth",wrap="Staged loose wrap",fourInHand="Four-in-hand seed"
    var id:String {rawValue}
}
struct ClothExperiment {
    let mesh:ClothMesh
    let fixed:[Int:V3]
    let grasp:ClothGrasp
    let capsules:[ClothCapsule]
    let floor:Double
    let kind:ClothCase
    func solver()->ClothSolver {
        var result=ClothSolver(mesh)
        result.pins=fixed.merging(grasp.targets){_,b in b}
        result.capsules=capsules;result.floor=floor
        if kind == .fourInHand {result.parameters.substeps=12;result.parameters.damping=80}
        if kind == .fold {result.parameters.substeps=12;result.parameters.damping=8;result.parameters.bending=0.000002}
        if kind == .wrap {result.parameters.substeps=12;result.parameters.damping=8;result.parameters.bending=0.000002}
        return result
    }
    static func make(_ kind:ClothCase,refineSeed:Bool=true,prepareSeed:Bool=true)->ClothExperiment {
        if kind == .wrap {return ClothWrapSequence.experiment()}
        let columns=5
        var rest:[SIMD2<Double>]=[],p:[V3]=[],indices:[[Int]]=[],rows=0,fixedRows:[Int]=[]
        var shapes:[ClothCapsule]=[]
        if kind == .strip {
            rows=41
            for i in 0..<rows {
                let s=Double(i)/Double(rows-1)*0.36,materialS=0.72+s,width=TieBlank.width(at:materialS*100)/100
                for j in 0..<columns {
                    let u=(Double(j)/Double(columns-1)-0.5)*width
                    rest.append(SIMD2(u,materialS))
                    p.append(V3(-u,0.20+sqrt(1-0.72*0.72)*min(s,0.36-s),-0.36*0.72/2+s*0.72))
                }
            }
            fixedRows=[0,1]
            shapes=[ClothCapsule(a:V3(-0.065,0.14,0),b:V3(0.065,0.14,0),radius:0.05)]
        } else if kind == .fold {
            rows=73;let radius=0.005,leg=0.12,length=2*leg + .pi*radius
            for i in 0..<rows {
                let s=Double(i)/Double(rows-1)*length,materialS=0.72+s,width=TieBlank.width(at:materialS*100)/100
                let y:Double,z:Double
                if s<=leg {y=0.15;z=s-leg}
                else if s<=leg + .pi*radius {let a=(s-leg)/radius;y=0.15+radius*(1-cos(a));z=radius*sin(a)}
                else {y=0.15+2*radius;z = -(s-leg - .pi*radius)}
                for j in 0..<columns {let u=(Double(j)/Double(columns-1)-0.5)*width;rest.append(SIMD2(u,materialS));p.append(V3(-u,y,z))}
                if s<leg-0.015 {fixedRows.append(i)}
            }
        } else {
            let model=FourInHand.build()
            var selected=Set(stride(from:0,to:model.samples.count,by:12));selected.insert(model.samples.count-1)
            for i in 1..<model.samples.count where model.samples[i].phase != model.samples[i-1].phase {selected.insert(i);selected.insert(i-1)}
            if refineSeed {
                // Refine the sampled geometry, not the deformed shape: retained
                // samples stay exactly on the authored strip and chart.
                for _ in 0..<8 {
                    let order=selected.sorted(),candidate=knotMesh(model,order:order,columns:columns)
                    let audit=ClothCollision.audit(candidate,candidate.initial)
                    if audit.intersections.isEmpty {break}
                    let before=selected.count
                    for pair in audit.intersections {for triangle in [pair.a,pair.b] {
                        let row=triangle/(2*(columns-1))
                        let a=order[row],b=order[row+1]
                        if b-a>1 {selected.insert((a+b)/2)}
                    }}
                    if selected.count==before {break}
                }
            }
            let samples=selected.sorted().map{model.samples[$0]};rows=samples.count
            for (i,sample) in samples.enumerated() {
                for j in 0..<columns {
                    let f=Double(j)/Double(columns-1)-0.5
                    rest.append(SIMD2(f*sample.chartWidth/100,sample.s/100))
                    p.append(RibbonSurface.position(sample,transverse:f*sample.width,side:0,kind:.fourInHand)/100)
                }
                if sample.center.y>5.5 && sample.phase<0 {fixedRows.append(i)}
            }
            // The neck portion is held, with no attraction to the rest of the authored knot.
            if fixedRows.isEmpty {fixedRows=[max(0,rows/5)]}
        }
        for i in 0..<rows-1 {for j in 0..<columns-1 {
            let a=i*columns+j,b=a+1,c=a+columns,d=c+1
            indices.append([a,b,c]);indices.append([b,d,c])
        }}
        var mesh=ClothMesh(rest:rest,positions:p,indices:indices)
        let fixed=Dictionary(uniqueKeysWithValues:fixedRows.flatMap{row in (0..<columns).map{(row*columns+$0,p[row*columns+$0])}})
        var grasp=ClothGrasp(vertices:Array((rows-2)*columns..<rows*columns),positions:p)
        if kind == .fold {grasp.held=false}
        if kind == .fourInHand && prepareSeed {
            mesh=prepareClearance(mesh,pins:fixed.merging(grasp.targets){_,b in b})
        }
        return ClothExperiment(mesh:mesh,fixed:fixed,grasp:grasp,capsules:shapes,floor:kind == .fourInHand ? -0.75:-0.18,kind:kind)
    }
    /// Explicit initial-condition preparation: contact only, no material solve or
    /// cosmetic smoothing. Every accepted correction has an intersection guard.
    private static func prepareClearance(_ mesh:ClothMesh,pins:[Int:V3])->ClothMesh {
        if !ClothCollision.audit(mesh,mesh.initial).intersections.isEmpty {return mesh}
        var solver=ClothSolver(mesh);solver.pins=pins
        for _ in 0..<16 {
            let old=solver.positions
            if ClothCollision.clearance(mesh,old,thickness:solver.parameters.thickness).violations==0 {break}
            solver.selfContacts(old:old,weights:solver.weights)
            let proposal=solver.positions;var accepted=false
            for backtrack in 0..<12 {
                let fraction=pow(0.5,Double(backtrack))
                let candidate=old.indices.map{old[$0]+(proposal[$0]-old[$0])*fraction}
                var budget=200_000
                if ClothCollision.swept(mesh,old,candidate,capsules:[],floor:nil,budget:&budget)==nil {
                    solver.positions=candidate;accepted=true;break
                }
            }
            if !accepted {solver.positions=old;break}
        }
        return ClothMesh(rest:mesh.rest,positions:solver.positions,indices:mesh.triangles.map{$0.ids})
    }
    private static func knotMesh(_ model:RibbonModel,order:[Int],columns:Int)->ClothMesh {
        var rest:[SIMD2<Double>]=[],p:[V3]=[],indices:[[Int]]=[]
        for i in order {let sample=model.samples[i]
            for j in 0..<columns {
                let f=Double(j)/Double(columns-1)-0.5
                rest.append(SIMD2(f*sample.chartWidth/100,sample.s/100))
                p.append(RibbonSurface.position(sample,transverse:f*sample.width,side:0,kind:.fourInHand)/100)
            }
        }
        for i in 0..<order.count-1 {for j in 0..<columns-1 {
            let a=i*columns+j,b=a+1,c=a+columns,d=c+1
            indices.append([a,b,c]);indices.append([b,d,c])
        }}
        return ClothMesh(rest:rest,positions:p,indices:indices)
    }
}
