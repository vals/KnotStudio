import Foundation
import simd
@main struct ClothKnotBoundProbe {
    static func main() {
        let e=ClothExperiment.make(.fourInHand)
        for fraction in [0.1,0.05,0.025,0.01] {
            var s=e.solver();s.parameters.projectionFraction=fraction
            let start=Date();var frames=0
            for _ in 0..<3 {if !s.advance(){break};frames+=1}
            let movement=zip(e.mesh.initial,s.positions).map{simd_length($0.0-$0.1)}.max() ?? 0
            print("fraction=\(fraction) frames=\(frames) moved=\(movement) RMS=\(s.snapshot().diagnostics.strainRMS) retries=\(s.retries) evaluations=\(s.collisionEvaluations) attempts=\(s.attemptFailures) wall=\(Date().timeIntervalSince(start))");fflush(stdout)
        }
    }
}
