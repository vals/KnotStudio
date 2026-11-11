import Foundation
import simd
@main struct ClothSafetyProbe {
    static func main() {
        for kind in [ClothCase.strip,.fold,.fourInHand] {
            let e=ClothExperiment.make(kind);var s=e.solver();let start=Date()
            print("\(kind.rawValue): \(e.mesh.initial.count) vertices");fflush(stdout)
            for frame in 1...(kind == .fourInHand ? 3:30) {
                let before=s.positions,t=s.time,ok=s.advance()
                if !ok {
                    print("STOP frame \(frame), retained=\(s.positions==before && s.time==t), retries=\(s.retries), checks=\(s.collisionEvaluations), reason=\(s.error ?? "none"), attempts=\(s.attemptFailures), wall=\(Date().timeIntervalSince(start))");fflush(stdout);break
                }
                if frame%10==0 || kind == .fourInHand {
                    let audit=ClothCollision.audit(e.mesh,s.positions),c=ClothCollision.clearance(e.mesh,s.positions,thickness:s.parameters.thickness)
                    let movement=zip(e.mesh.initial,s.positions).map{simd_length($0.0-$0.1)}.max() ?? 0
                    print("frame=\(frame) t=\(s.time) moved=\(movement) intersections=\(audit.intersections.count) clearance=\(c.minimum) violations=\(c.violations) RMS=\(s.snapshot().diagnostics.strainRMS) retries=\(s.retries) checks=\(s.collisionEvaluations) wall=\(Date().timeIntervalSince(start))");fflush(stdout)
                }
            }
        }
    }
}
