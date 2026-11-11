import Foundation
import simd
@main struct ClothTimestepProbe {
    static func main() {
        let e=ClothExperiment.make(.strip)
        var results:[[V3]]=[]
        for steps in [3,6,12,24] {
            var s=e.solver();s.parameters.substeps=steps;s.parameters.selfContact=false
            for _ in 0..<30 {if !s.advance(){print(s.error ?? "failed");break}}
            print("substeps=\(steps) t=\(s.time) RMS=\(s.snapshot().diagnostics.strainRMS)")
            results.append(s.positions)
        }
        for i in 0..<results.count-1 {
            var sum=0.0
            for j in e.mesh.initial.indices {sum+=simd_length(results[i][j]-results[i+1][j])}
            let diff=sum/Double(e.mesh.initial.count)
            print("comparison \([3,6,12][i]) -> \([6,12,24][i]): \(diff) m")
        }
    }
}
