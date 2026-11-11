import Foundation
import simd

/// Turns ribbon cross-sections into render buffers. One strip, fifteen
/// vertices across: a flat visible band, a tight roll at each edge and the
/// hem that continues underneath. Buffers are reused between frames.
final class RibbonMesh {
    static let columns = 15

    /// A smooth map of space applied to every vertex: it plumps the flat stack
    /// into a cushion and tapers the knot toward the bottom. Because it only
    /// rescales depth and width, it cannot reorder layers.
    struct Shape {
        var yCenter = -1.6
        var radiusX = 2.8
        var radiusY = 3.2
        var bulge = 1.2
        var taper = 0.16
        var mirror = false
        @inline(__always) func apply(_ p: V3) -> V3 {
            let u = (p.y - yCenter) / radiusY
            let v = p.x / radiusX
            let r2 = u * u + v * v
            var q = p
            if r2 < 1 { let f = 1 - r2; q.z *= 1 + bulge * f * f }
            q.x *= 1 + taper * 1.6 * u * exp(-u * u)
            return q
        }
    }

    private(set) var positions: [Float] = []
    private(set) var normals: [Float] = []
    /// Material coordinates in cm: (across, along).
    private(set) var chart: [Float] = []
    private(set) var front: [UInt32] = []
    private(set) var back: [UInt32] = []
    private(set) var rowCount = 0
    var vertexCount: Int { positions.count / 3 }
    var triangleCount: Int { (front.count + back.count) / 3 }

    private var grid: [V3] = []
    private var pa = [Double](repeating: 0, count: RibbonMesh.columns)
    private var pb = [Double](repeating: 0, count: RibbonMesh.columns)
    private var pt = [Double](repeating: 0, count: RibbonMesh.columns)

    private func fillProfile(_ row: Row) {
        let wv = max(row.wv, 0)
        let rho = min(0.07, wv / 10)
        let hem = min(0.45, wv * 0.2)
        let half = wv / 2 + hem
        let wr = min(max(row.wr, 0), wv)
        let h = max(wr / 2 - rho, 0)
        let arc = Double.pi * rho
        let flap = max(half - h - arc, 0)
        let reach = min(flap, 1.9 * h)
        pt[0] = -(h + arc + flap); pa[0] = -(h - reach); pb[0] = -2 * rho
        pt[1] = -(h + arc); pa[1] = -h; pb[1] = -2 * rho
        pt[14] = h + arc + flap; pa[14] = h - reach; pb[14] = -2.6 * rho
        pt[13] = h + arc; pa[13] = h; pb[13] = -2 * rho
        let third = Double.pi / 3
        for (k, phi) in [(3, third), (2, 2 * third)] {
            let x = h + rho * sin(phi), y = -rho * (1 - cos(phi))
            pt[k] = -(h + rho * phi); pa[k] = -x; pb[k] = y
            pt[14 - k] = h + rho * phi; pa[14 - k] = x; pb[14 - k] = y
        }
        for k in 0...6 {
            let xi = Double(k - 3) / 3
            pt[4 + k] = xi * h; pa[4 + k] = xi * h; pb[4 + k] = 0
        }
        // Cup the section into an arc: its length stays wr, its chord shrinks.
        if wr > 0.2 && row.chord < wr - 1e-3 {
            let ratio = max(row.chord / wr, 0.25)
            var alpha = min(2.4, max(0.05, (6 * (1 - ratio)).squareRoot()))
            for _ in 0..<4 {
                let f = sin(alpha) / alpha - ratio
                let df = (alpha * cos(alpha) - sin(alpha)) / (alpha * alpha)
                if abs(df) > 1e-9 { alpha = min(2.6, max(0.02, alpha - f / df)) }
            }
            let radius = (wr / 2) / alpha
            // The edges stay on the centreline plane and the middle swells
            // toward the patterned side, so a cupped blade never dips into
            // whatever hangs behind it. The dimple is a dent in that swell and
            // is limited to it for the same reason.
            let rise = radius * (1 - cos(alpha))
            let dent = min(row.dimple, 0.85 * rise)
            if dent > 1e-4 {
                let sigma = 0.16 * wv + 0.25
                for k in 0..<RibbonMesh.columns { let x = pa[k] / sigma; pb[k] -= dent * exp(-x * x) }
            }
            for k in 0..<RibbonMesh.columns {
                let psi = pa[k] / radius
                let b = pb[k]
                pa[k] = (radius + b) * sin(psi)
                pb[k] = b * cos(psi) - radius * (1 - cos(psi)) + rise
            }
        }
    }

    func build(rows: [Row], shape: Shape) {
        let cols = RibbonMesh.columns
        let n = rows.count
        rowCount = n
        let sign: Double = shape.mirror ? -1 : 1
        grid.removeAll(keepingCapacity: true)
        chart.removeAll(keepingCapacity: true)
        grid.reserveCapacity(n * cols)
        for row in rows {
            fillProfile(row)
            let ruling = row.a + row.t * row.kappa
            for k in 0..<cols {
                var p = shape.apply(row.c + ruling * pa[k] + row.n * pb[k])
                p.x *= sign
                grid.append(p)
                chart.append(Float(pt[k] * sign))
                chart.append(Float(row.s + pa[k] * row.kappa))
            }
        }
        let count = n * cols
        positions.removeAll(keepingCapacity: true)
        normals.removeAll(keepingCapacity: true)
        positions.reserveCapacity(count * 6)
        normals.reserveCapacity(count * 6)
        for p in grid { positions.append(Float(p.x)); positions.append(Float(p.y)); positions.append(Float(p.z)) }
        for i in 0..<n {
            let up = max(i - 1, 0) * cols, down = min(i + 1, n - 1) * cols
            for k in 0..<cols {
                let l = i * cols + max(k - 1, 0), r = i * cols + min(k + 1, cols - 1)
                let normal = unit(simd_cross(grid[r] - grid[l], grid[down + k] - grid[up + k])) * sign
                normals.append(Float(normal.x)); normals.append(Float(normal.y)); normals.append(Float(normal.z))
            }
        }
        // The reverse face: same points, opposite normals.
        positions.append(contentsOf: positions[0..<(count * 3)])
        for i in 0..<(count * 3) { normals.append(-normals[i]) }
        chart.append(contentsOf: chart[0..<(count * 2)])

        front.removeAll(keepingCapacity: true)
        back.removeAll(keepingCapacity: true)
        guard n > 1 else { return }
        let offset = UInt32(count)
        for i in 0..<(n - 1) {
            for k in 0..<(cols - 1) {
                let a = UInt32(i * cols + k), b = a + 1, c = a + UInt32(cols), d = c + 1
                if shape.mirror {
                    front.append(contentsOf: [a, c, b, b, c, d])
                    back.append(contentsOf: [a + offset, b + offset, c + offset, b + offset, d + offset, c + offset])
                } else {
                    front.append(contentsOf: [a, b, c, b, d, c])
                    back.append(contentsOf: [a + offset, c + offset, b + offset, b + offset, c + offset, d + offset])
                }
            }
        }
    }
}
