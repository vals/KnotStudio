import Foundation
import simd

/// The loop the tie makes around the neck: an ellipse, lower at the front.
struct NeckRing: Equatable {
    var rx = 6.0, rz = 6.4
    var zc = -8.0
    var yFront = 3.6
    var rise = 3.2
    func point(_ th: Double, inset: Double = 0) -> V3 {
        V3(-(rx - inset) * sin(th), yFront + rise * (1 - cos(th)) / 2, zc + (rz - inset) * cos(th))
    }
    var frontZ: Double { zc + rz }
}

/// A plain shirt collar: a stand inside the tie's loop and a leaf that stands
/// up while tying (out of the way of the centre moves) and folds down over
/// the tie once the knot is dressed.
enum Collar {
    static func build(neck: NeckRing, fold: Double, positions: inout [Float], normals: inout [Float], indices: inout [UInt32]) {
        positions.removeAll(keepingCapacity: true)
        normals.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)
        func grid(_ nu: Int, _ nv: Int, _ point: (Double, Double) -> V3) {
            let base = UInt32(positions.count / 3)
            var pts: [V3] = []
            for i in 0...nu { for j in 0...nv { pts.append(point(Double(i) / Double(nu), Double(j) / Double(nv))) } }
            let stride = nv + 1
            for i in 0...nu {
                for j in 0...nv {
                    let p = pts[i * stride + j]
                    let du = pts[min(i + 1, nu) * stride + j] - pts[max(i - 1, 0) * stride + j]
                    let dv = pts[i * stride + min(j + 1, nv)] - pts[i * stride + max(j - 1, 0)]
                    let n = unit(simd_cross(du, dv))
                    positions.append(contentsOf: [Float(p.x), Float(p.y), Float(p.z)])
                    normals.append(contentsOf: [Float(n.x), Float(n.y), Float(n.z)])
                }
            }
            for i in 0..<nu {
                for j in 0..<nv {
                    let a = base + UInt32(i * stride + j), b = a + 1, c = a + UInt32(stride), d = c + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
        }
        let standLow = 1.7, standHigh = 1.9, inset = 0.3
        func top(_ th: Double) -> V3 { neck.point(th, inset: inset) + V3(0, standHigh, 0) }
        grid(72, 2) { u, v in
            neck.point(u * 2 * Double.pi, inset: inset) + V3(0, mix(-standLow, standHigh, v), 0)
        }
        let eased = smoothstep(0, 1, fold)
        let angle = mix(0.0, Double.pi - 0.10, eased)
        for side in [1.0, -1.0] {
            grid(30, 7) { u, v in
                // The front edges spread apart toward the points when folded down.
                let gap = 0.10 + mix(0.10, 0.55, eased) * v
                let local = mix(gap, Double.pi, u)
                let th = side > 0 ? local : 2 * Double.pi - local
                let height = mix(6.6, 4.4, smoothstep(0.3, 1.7, local))
                let out = unit(V3(-sin(th), 0, cos(th)))
                let direction = V3(0, 1, 0) * cos(angle) + out * sin(angle)
                // A soft roll at the fold line rather than a hard hinge.
                // Folded, the leaf stands clear of the tie beneath it, and further
                // clear toward the front where the tie comes forward to the knot.
                let lift = (1.5 + 1.2 * (1 - smoothstep(0.25, 1.3, local))) * eased * smoothstep(0, 0.3, v)
                return top(th) + direction * (height * v) + out * lift + V3(0, 0.25 * eased * sin(Double.pi * min(1, v * 4)) , 0)
            }
        }
    }
}
