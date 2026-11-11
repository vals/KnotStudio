import Foundation
import simd

@main
struct Checks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            if !condition() { fputs("FAIL: \(message)\n",stderr); exit(1) }
        }
        // Independent enumeration of all 3–9 move region words and both polarities.
        var valid:Set<String> = []
        func enumerate(_ word: String, _ length: Int) {
            if word.count == length {
                for firstIn in [true,false] {
                    let text = word.enumerated().map { i,c in String(c) + ((i%2 == 0) == firstIn ? "i" : "o") }.joined()+"T"
                    if let sequence = try? TieSequence(text) { valid.insert(sequence.notation) }
                }
                return
            }
            for region in ["L","R","C"] where word.last.map(String.init) != region { enumerate(word+region,length) }
        }
        for length in 3...9 { enumerate("L",length) }
        check(valid.count == 85,"FM enumeration must produce 85, got \(valid.count)")
        for invalid in ["", "LiRoLiCo", "RiLoRiCoT", "LiLiCoT", "LoRoLiCoT", "LiRoCiT", "LiRoLiCoTT", "LiRoXiCoT", "LiRoLiCoTx"] {
            check((try? TieSequence(invalid)) == nil,"reject malformed sequence \(invalid)")
        }
        let normalized = try TieSequence(" Li Ro Li Co T ")
        check(normalized.notation == "LiRoLiCoT","whitespace normalization")
        var signatures:Set<String> = []
        for knot in KnotKind.allCases {
            let seq = try TieSequence(knot.notation), model = RibbonBuilder.build(knot)
            check(valid.contains(seq.notation),"preset belongs to enumerated FM family")
            check(model.crossings.map(\.token) == seq.moves.map(\.token),"complete unreduced move list")
            check(model.samples.first!.s == 0,"material origin")
            check(model.length > 45 && model.length < 160,"reasonable chart length")
            for (i,sample) in model.samples.enumerated() {
                check(sample.center.x.isFinite && sample.center.y.isFinite && sample.center.z.isFinite,"finite geometry")
                check(sample.width > 0,"positive width")
                check(abs(simd_length(sample.normal)-1) < 1e-6,"unit material normal")
                check(abs(simd_length(sample.across)-1) < 1e-6,"unit width frame")
                check(abs(simd_dot(sample.across,sample.normal)) < 1e-6,"perpendicular material frame")
                if i > 0 {
                    let previous = model.samples[i-1]
                    check(sample.s > previous.s,"strictly increasing longitudinal coordinate")
                    check(abs(sample.referenceArc-previous.referenceArc-simd_length(sample.center-previous.center)) < 1e-8,"canonical arc-length accumulation")
                    check(simd_dot(sample.across,previous.across) > 0.45,"no abrupt frame flips: \(knot.rawValue) index \(i) dot \(simd_dot(sample.across,previous.across)) positions \(sample.center) / \(previous.center)")
                }

            }
            for crossing in model.crossings {
                check((crossing.anchor.z > 0) == seq.moves[crossing.moveIndex].inward,"in/out anchor depth sign")
            }
            let blade = model.samples.last!
            check(blade.normal.z > 0.9,"front face outward at blade")
            check((model.samples[20].normal.z < 0) == seq.undersideAtNeck,"front/back parity at passive tail")
            signatures.insert(model.crossings.map { String(format:"%.3f,%.3f,%.3f",$0.anchor.x,$0.anchor.y,$0.anchor.z) }.joined(separator:";"))
            print("\(knot.rawValue): \(seq.notation), \(model.samples.count) rows, \(String(format:"%.2f",model.length)) cm canonical chart")
        }
        check(signatures.count == 4,"four different full routes")
        let four = RibbonBuilder.build(.fourInHand)
        func central(_ phase: Int) -> RibbonSample {
            four.samples.filter { $0.phase == phase && $0.center.y < 1.2 && $0.center.y > 0 }.min { abs($0.center.x) < abs($1.center.x) }!
        }
        let firstCross = central(0), backWrap = central(1), facade = central(2)
        let tuck = four.samples.filter { $0.phase == 4 }.min { abs($0.center.y-0.55) < abs($1.center.y-0.55) }!
        check(backWrap.center.z < -0.5,"Ro passes behind passive strand")
        check(firstCross.center.z > 0.1,"initial Li passes in front")
        check(tuck.center.z > firstCross.center.z+0.15,"tuck stays in front of inner crossing")
        check(tuck.center.z < facade.center.z-0.3,"tuck passes behind the front wrap")
        check(facade.normal.z > 0.95 && tuck.normal.z > 0.95,"front face visible on facade and blade")
        check(firstCross.s < backWrap.s && backWrap.s < facade.s && facade.s < tuck.s,"unreduced material order through wraps and tuck")
        check(four.samples.allSatisfy { $0.width > 0 && $0.s.isFinite },"continuous strip has no discarded inner rows")
        let a = RibbonBuilder.uv(transverse:1,s:20,repeatCM:4,offsetCM:0,angle:0)
        let b = RibbonBuilder.uv(transverse:2,s:20,repeatCM:4,offsetCM:0,angle:0)
        let c = RibbonBuilder.uv(transverse:1,s:24,repeatCM:4,offsetCM:0,angle:0)
        check(abs((b-a).x+0.25) < 1e-9,"constant physical scale across different widths")
        check(abs((c-a).y-1) < 1e-9,"one repeat per 4 cm along fabric")
        let mesh=RibbonMesh(four), spread=RibbonMesh(four,spread:2), baseline=RibbonMesh(four,refined:false)
        check(mesh.chart == spread.chart && mesh.chart == baseline.chart,"actual mesh chart remains fixed under inspection and shaping")
        check(mesh.positions != spread.positions && mesh.positions != baseline.positions,"deformations actually change mesh positions")
        let coordinates=mesh.textureCoordinates(repeatCM:4,offsetCM:1,angle:0,aspect:0.5)
        let shifted=mesh.textureCoordinates(repeatCM:4,offsetCM:3,angle:0,aspect:0.5)
        let rotated=mesh.textureCoordinates(repeatCM:4,offsetCM:0,angle:Double.pi/2,aspect:0.5)
        let faceSize=mesh.rowWidth*mesh.rowCount
        for i in stride(from:0,to:faceSize,by:mesh.rowWidth) {
            let row=i/mesh.rowWidth, sample=four.samples[row]
            check(abs(mesh.chart[i+mesh.rowWidth-1].x-mesh.chart[i].x-sample.chartWidth)<1e-9,"full flat width retained in rendered chart")
            check(mesh.chart[i] == mesh.chart[i+faceSize],"both faces share material coordinates")
            check(abs((shifted[i]-coordinates[i]).y-1)<1e-9,"actual mesh offset advances one non-square tile")
            check(abs(rotated[i].x-0.5+sample.s/4)<1e-9,"actual mesh angle rotates longitudinal axis into U")
            if row>0 && row<mesh.rowCount-1 {
                let tangent=unit(four.samples[row+1].center-four.samples[row-1].center)
                check(abs(simd_dot(sample.across,tangent))<0.85,"bounded four-in-hand route skew")
            }
        }
        let flat=RibbonMesh(four,flat:true)
        check(flat.chart==mesh.chart,"flat and tied views share the complete material domain")
        for i in stride(from:0,to:faceSize,by:37) {
            check(abs(flat.positions[i].x+flat.chart[i].x)<1e-9 && abs(flat.positions[i].y-(72.5-flat.chart[i].y))<1e-9,"flat view is an undistorted material chart")
        }
        check(abs(four.length-145)<1e-9,"explicit assumed blank length")
        // Every edge must occur twice with opposing directions: includes tip caps.
        var edges:[String:Int]=[:], incidence:[String:Int]=[:]
        let indices=mesh.front+mesh.back+mesh.edges
        for triangle in stride(from:0,to:indices.count,by:3) {
            for k in 0..<3 {
                let a=indices[triangle+k],b=indices[triangle+(k+1)%3]
                let key="\(min(a,b)),\(max(a,b))"
                edges[key,default:0] += a<b ? 1 : -1
                incidence[key,default:0] += 1
            }
        }
        check(incidence.values.allSatisfy{$0==2} && edges.values.allSatisfy{$0==0},"closed mesh with consistently oriented edge and tip caps")
        for t in stride(from:0,to:mesh.front.count,by:3) {
            let ids=(0..<3).map{Int(mesh.front[t+$0])}
            let normal=simd_cross(mesh.positions[ids[1]]-mesh.positions[ids[0]],mesh.positions[ids[2]]-mesh.positions[ids[0]])
            check(simd_length(normal)>1e-12,"nondegenerate front triangle")
        }
        print("PASS: \(count) assertions; all 85 FM sequences; four routes; frame, chart, depth and face checks.")
    }
}
