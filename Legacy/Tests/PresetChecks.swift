import Foundation
import simd

@main
struct PresetChecks {
    static func main() {
        func check(_ condition:Bool,_ message:String) {
            guard condition else {fputs("FAIL: \(message)\n",stderr);exit(1)}
            print("PASS: \(message)")
        }
        let model=PremadeFourInHand.build(),m=model.mesh
        let separated=PremadeFourInHand.build(spread:2).mesh
        let flat=PremadeFourInHand.build(flat:true)
        check(m.positions == PremadeFourInHand.build().mesh.positions,"deterministic authored mesh")
        check(m.chart == separated.chart && m.positions != separated.positions,"inspection changes positions, preserving every material coordinate")
        check(zip(m.positions,m.normals).allSatisfy {p,n in p.x.isFinite && p.y.isFinite && p.z.isFinite && abs(simd_length(n)-1)<1e-8},"finite surface and unit normals")
        var minArea=Double.infinity
        for f in [m.front,m.back,m.edges] {
            for i in stride(from:0,to:f.count,by:3) {
                let a=m.positions[Int(f[i])],b=m.positions[Int(f[i+1])],c=m.positions[Int(f[i+2])]
                minArea=min(minArea,simd_length(simd_cross(b-a,c-a))/2)
            }
        }
        check(minArea>1e-11,"no degenerate emitted triangles (including thin panel edges)")
        let wrap=model.parts.first{$0.name == "front wrap"}!,blade=model.parts.first{$0.name == "blade"}!
        func mid(_ part:PremadeFourInHand.Part,_ row:Int,_ col:Int)->V3 {
            let i=part.first+row*part.columns+col
            return (m.positions[i]+m.positions[i+part.count])/2
        }
        // Sample the two silhouette meridians, independently of normal/UV helpers.
        let leftTop=mid(wrap,wrap.rows*3/4,wrap.columns-1)
        let rightTop=mid(wrap,wrap.rows/4,wrap.columns-1)
        check(rightTop.y-leftTop.y>0.7,"unequal shoulders lean upward to the right")
        let leftBottom=mid(wrap,wrap.rows*3/4,0),rightBottom=mid(wrap,wrap.rows/4,0)
        let ratio=(rightBottom.x-leftBottom.x)/(rightTop.x-leftTop.x)
        check(ratio>0.48 && ratio<0.66,"exit stays narrow without collapsing into a point (width ratio \(String(format:"%.3f",ratio)))")
        let dimpleRow=Int(3.0/44.5*Double(blade.rows-1))
        let center=mid(blade,dimpleRow,32),left=mid(blade,dimpleRow,16),right=mid(blade,dimpleRow,48)
        check(left.z-center.z>0.30 && right.z-center.z>0.30,"blade dimple is recessed between two rounded folds")
        let releasedRow=Int(5.5/44.5*Double(blade.rows-1))
        let releasedCenter=mid(blade,releasedRow,32)
        let releasedFold=max(mid(blade,releasedRow,16).z,mid(blade,releasedRow,48).z)-releasedCenter.z
        check(releasedFold<0.02,"gathering releases below the short dimple, without long parallel pleats")
        var worstArcError=0.0
        for row in 0..<blade.rows-1 {
            var arc=0.0
            for col in 0..<blade.columns-1 {arc+=simd_length(mid(blade,row,col+1)-mid(blade,row,col))}
            let start=blade.first+row*blade.columns
            let materialWidth=m.chart[start+blade.columns-1].x-m.chart[start].x
            worstArcError=max(worstArcError,abs(arc/materialWidth-1))
        }
        check(worstArcError<0.003,"folded blade preserves transverse material length (max error \(String(format:"%.4f%%",worstArcError*100)))")
        let flatBlade=flat.parts[0]
        check(Array(m.chart[blade.first..<blade.first+blade.count]) == Array(flat.mesh.chart[flatBlade.first..<flatBlade.first+flatBlade.count]),"flat blade has exactly the tied blade’s chart")
        // Front-view rays through the upper blade must hit the wrap first.
        let triangles=m.front.filter {Int($0)>=wrap.first && Int($0)<wrap.first+wrap.count}
        func frontZ(_ p:V3)->Double? {
            var depth:Double?
            for t in stride(from:0,to:triangles.count,by:3) {
                let a=m.positions[Int(triangles[t])],b=m.positions[Int(triangles[t+1])],c=m.positions[Int(triangles[t+2])]
                let den=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
                if abs(den)<1e-12 {continue}
                let u=((b.y-c.y)*(p.x-c.x)+(c.x-b.x)*(p.y-c.y))/den
                let v=((c.y-a.y)*(p.x-c.x)+(a.x-c.x)*(p.y-c.y))/den
                if u>=0 && v>=0 && u+v<=1 {
                    let z=u*a.z+v*b.z+(1-u-v)*c.z
                    depth=max(depth ?? -Double.infinity,z)
                }
            }
            return depth
        }
        var covered=true,minimumGap=Double.infinity
        for row in 0...9 {for col in stride(from:0,to:blade.columns,by:4) {
            let p=m.positions[blade.first+row*blade.columns+col]
            if let z=frontZ(p) {minimumGap=min(minimumGap,z-p.z);covered=covered && z>p.z+0.02}
            else {covered=false}
        }}
        check(covered,"upper tucked blade is occluded by the front wrap (min depth gap \(String(format:"%.3f",minimumGap)) cm)")
        print("These checks constrain a visual preset; they do not certify cloth mechanics or global topology.")
    }
}
