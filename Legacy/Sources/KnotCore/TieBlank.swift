import Foundation

/// An explicitly assumed flat blank, not inferred from the tied centerline.
/// Every transverse sample spans this full domain even in compressed folds.
enum TieBlank {
    static let lengthCM = 145.0
    static let profile: [(Double,Double)] = [(0,0.04),(0.018,3.1),(0.28,2.2),(0.40,1.8),(0.55,2.6),(0.80,5.4),(0.975,7.1),(1,0.035)]
    static func width(at s:Double)->Double {
        let f=min(1,max(0,s/lengthCM))
        for pair in zip(profile,profile.dropFirst()) where f <= pair.1.0 {
            let t=(f-pair.0.0)/(pair.1.0-pair.0.0)
            return pair.0.1+(pair.1.1-pair.0.1)*t
        }
        return profile.last!.1
    }
}
