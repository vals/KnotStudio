import Foundation
import simd

typealias V3 = SIMD3<Double>
typealias V2 = SIMD2<Double>

@inline(__always) func unit(_ v: V3) -> V3 {
    let n = simd_length(v)
    return n > 1e-12 ? v / n : V3(0, 0, 1)
}
@inline(__always) func unit(_ v: V2) -> V2 {
    let n = simd_length(v)
    return n > 1e-12 ? v / n : V2(1, 0)
}
@inline(__always) func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func mix(_ a: V2, _ b: V2, _ t: Double) -> V2 { a + (b - a) * t }
@inline(__always) func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
@inline(__always) func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
@inline(__always) func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
@inline(__always) func v3(_ p: V2, _ z: Double) -> V3 { V3(p.x, p.y, z) }

/// The assumed flat tie: visible width along the length, narrow tip at s = 0.
enum TieBlank {
    static let length = 147.0
    static let profile: [(Double, Double)] = [
        (0, 0), (2.0, 3.6), (40, 3.0), (62, 2.8), (80, 3.3), (98, 4.8),
        (120, 6.6), (138, 8.4), (142.6, 8.8), (147, 0),
    ]
    static func width(_ s: Double) -> Double {
        if s <= 0 || s >= length { return 0 }
        var i = 1
        while i < profile.count - 1 && profile[i].0 < s { i += 1 }
        let a = profile[i - 1], b = profile[i]
        return a.1 + (b.1 - a.1) * (s - a.0) / (b.0 - a.0)
    }
}

/// One cross-section of the ribbon. `a` is the material's across direction,
/// `n` the normal of the patterned face. The surface point at ruling
/// coordinate x is `c + x * (a + kappa * t)`: sheared rulings let a row lie
/// along an oblique fold line without stretching the cloth.
struct Row {
    var c: V3
    var t: V3
    var a: V3
    var n: V3
    var kappa = 0.0
    /// Material coordinate along the tie, cm from the narrow tip.
    var s = 0.0
    /// Flat width of the blank here.
    var wv = 0.0
    /// Width left flat; the rest of the blank is rolled under the edges.
    var wr = 0.0
    /// Chord of the cupped cross-section (equals `wr` when flat).
    var chord = 0.0
    var dimple = 0.0
}
