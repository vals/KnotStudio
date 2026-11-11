import Foundation
@main struct ClothProbe {
    static func main() {
        let e=ClothExperiment.make(.fourInHand)
        var s=e.solver();let start=Date()
        for frame in 1...30 {
            if !s.advance() {print("STOP frame \(frame): \(s.error ?? "failed")");break}
            if frame%5==0 {
                let d=s.snapshot().diagnostics
                print("frame=\(frame) RMS=\(d.strainRMS) maxSpeed=\(d.maxSpeed) shear=\(d.shearMax) wall=\(Date().timeIntervalSince(start))");fflush(stdout)
            }
        }
    }
}
