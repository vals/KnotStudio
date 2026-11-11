import Foundation
import simd

/// Rendering geometry is separate from the canonical material chart. Every face,
/// edge and inspection trace goes through the same continuous spatial map.
enum RibbonSurface {
    static let acrossCount = 24
    static let halfThickness = 0.025

    static func smooth(_ a: Double, _ b: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value-a)/(b-a)))
        return t*t*(3-2*t)
    }

    /// A monotone vertical compression closes the upper loop. x is unchanged;
    /// z has a strictly positive scale plus a smooth offset. Thus this map is
    /// one-to-one; it cannot make separate points of the original strip coincide.
    /// It is an authored shape correction, not a material-preserving cloth solve.
    static func shape(_ p: V3, kind: KnotKind, refined: Bool = true) -> V3 {
        guard kind == .fourInHand && refined else { return p }
        let compress = 0.62 * smooth(1.05, 2.55, p.y)
        let release = 0.62 * smooth(2.65, 5.6, p.y)
        let y = p.y - compress + release
        let envelope = smooth(-4.0,-1.4,p.y) * (1-smooth(2.5,5.0,p.y))
        let depthScale = 1 - 0.28*envelope
        // A small continuous groove passes from the wrap into the blade.
        // This displaces both fabric faces and all interior layers together.
        let dimple = 0.105 * exp(-pow((p.y+0.85)/1.15,2)) * (1-1.8*exp(-pow((p.x+0.05)/0.30,2)))
        let softEdge = 0.035 * sin(p.x*2.0) * exp(-pow((p.y-0.45)/1.7,2))
        return V3(p.x,y,p.z*depthScale+dimple+softEdge)
    }

    static func position(_ sample: RibbonSample, transverse: Double, side: Double,
                         kind: KnotKind, spread: Double = 0, refined: Bool = true) -> V3 {
        let fraction = transverse/max(0.01,sample.width/2)
        let crown = 0.035*(1-fraction*fraction)
        let base = sample.center + sample.across*transverse + sample.normal*(side*halfThickness+crown)
        var p = shape(base,kind:kind,refined:refined)
        // Inspection happens after the common shape map; it never changes UVs.
        if sample.phase >= 0 && sample.center.y > -2 {
            let fade = min(1,max(0,(sample.center.y+2)/2))
            p.z += spread*fade*(Double(sample.phase)*0.58-1)
            p.x *= 1+spread*0.13*fade
        }
        return p
    }
}

struct RibbonMesh {
    let positions: [V3]
    let normals: [V3]
    /// Raw transverse and longitudinal centimeters, shared by both faces.
    let chart: [SIMD2<Double>]
    let front: [Int32]
    let back: [Int32]
    let edges: [Int32]
    let rowWidth: Int
    let rowCount: Int

    /// Direct surface panels for premade visual presets. Legacy ribbon rows
    /// remain unchanged and continue to supply the experimental solver seed.
    init(positions:[V3],normals:[V3],chart:[SIMD2<Double>],front:[Int32],back:[Int32],edges:[Int32]) {
        self.positions=positions;self.normals=normals;self.chart=chart
        self.front=front;self.back=back;self.edges=edges;rowWidth=0;rowCount=0
    }

    init(_ model: RibbonModel, spread: Double = 0, refined: Bool = true, flat: Bool = false) {
        rowWidth=RibbonSurface.acrossCount+1; rowCount=model.samples.count
        let faceSize=rowWidth*rowCount
        var p:[V3]=[],uv:[SIMD2<Double>]=[]
        for side in [1.0,-1.0] {
            for sample in model.samples {
                for j in 0..<rowWidth {
                    let t=(Double(j)/Double(rowWidth-1)-0.5)*sample.width
                    let materialT=(Double(j)/Double(rowWidth-1)-0.5)*sample.chartWidth
                    p.append(flat ? V3(-materialT,model.length/2-sample.s,side*RibbonSurface.halfThickness) : RibbonSurface.position(sample,transverse:t,side:side,kind:model.kind,spread:spread,refined:refined))
                    uv.append(SIMD2(materialT,sample.s))
                }
            }
        }
        var f:[Int32]=[],b:[Int32]=[],e:[Int32]=[]
        for i in 0..<(rowCount-1) {
            for j in 0..<(rowWidth-1) {
                let a=Int32(i*rowWidth+j),c=a+Int32(rowWidth),d=c+1
                f += [a,a+1,c,a+1,d,c]
                let o=Int32(faceSize)
                b += [a+o,c+o,a+1+o,a+1+o,c+o,d+o]
            }
            for j in [0,rowWidth-1] {
                let a=Int32(i*rowWidth+j),b=a+Int32(rowWidth),c=a+Int32(faceSize),d=b+Int32(faceSize)
                e += j==0 ? [a,b,c,b,d,c] : [a,c,b,b,c,d]
            }
        }
        // Close the two tips as well as the long ribbon edges.
        for row in [0,rowCount-1] {
            for j in 0..<(rowWidth-1) {
                let a=Int32(row*rowWidth+j),b=a+1,c=a+Int32(faceSize),d=c+1
                e += row==0 ? [a,c,b,b,c,d] : [a,b,c,b,d,c]
            }
        }
        // Actual surface tangents, including the transverse crown and shape map.
        // The old constant row normal made curved cloth look like a hard shell.
        var n=[V3](repeating:.zero,count:p.count)
        for face in 0..<2 {
            let offset=face*faceSize,sign=face==0 ? 1.0 : -1.0
            for i in 0..<rowCount { for j in 0..<rowWidth {
                let left=offset+i*rowWidth+max(0,j-1),right=offset+i*rowWidth+min(rowWidth-1,j+1)
                let previous=offset+max(0,i-1)*rowWidth+j,next=offset+min(rowCount-1,i+1)*rowWidth+j
                n[offset+i*rowWidth+j]=unit(simd_cross(p[right]-p[left],p[next]-p[previous]))*sign
            }}
        }
        positions=p; normals=n; chart=uv; front=f; back=b; edges=e
    }

    func textureCoordinates(repeatCM:Double,offsetCM:Double,angle:Double,aspect:Double=1)->[SIMD2<Double>] {
        chart.map { RibbonBuilder.uv(transverse:$0.x,s:$0.y,repeatCM:repeatCM,offsetCM:offsetCM,angle:angle,aspect:aspect) }
    }
}
