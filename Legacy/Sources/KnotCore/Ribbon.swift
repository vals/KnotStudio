import Foundation
import simd

typealias V3 = SIMD3<Double>
func unit(_ v: V3) -> V3 { let n = simd_length(v); return n > 1e-10 ? v / n : V3(1, 0, 0) }
struct Control {
    var p: V3
    var width: Double
    var phase: Int // -1 neck/passive; zero based move; moves.count tuck/blade
}
struct RibbonSample {
    var center: V3
    var across: V3
    var normal: V3
    var width: Double
    var s: Double // fixed material coordinate, in cm
    var phase: Int
    var materialWidth: Double? = nil
    var routeS: Double? = nil
    var chartWidth: Double { materialWidth ?? width }
    var referenceArc: Double { routeS ?? s }
}
struct Crossing {
    let token: String
    let anchor: V3
    let moveIndex: Int
}
struct RibbonModel {
    let kind: KnotKind
    let samples: [RibbonSample]
    let crossings: [Crossing]
    var length: Double { samples.last?.s ?? 0 }
}

/// Four explicitly supported route templates. Their controls encode the full move
/// list, including hidden wraps. They are geometric embeddings, not settled cloth.
enum RibbonBuilder {
    static func build(_ kind: KnotKind) -> RibbonModel {
        if kind == .fourInHand { return FourInHand.build() }
        let moves = kind.sequence.moves
        let broad = kind == .windsor ? 1.18 : kind == .halfWindsor ? 1.08 : kind == .pratt ? 1.02 : 0.94
        var points: [Control] = []
        func add(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ phase: Int = -1) {
            points.append(Control(p: V3(x, y, z), width: w, phase: phase))
        }
        // Follow one continuous open strip: narrow tip -> neck -> active moves -> wide tip.
        add(0, -14.5, -0.8, 0.05)
        add(0, -13.6, -0.8, 2.5)
        add(0, -6, -0.75, 2.0)
        add(0, 0.45, 0, 1.45)
        add(-1.15, 3.0, 0, 1.35)
        add(-2.25, 5.05, -1.0, 1.3)
        add(-1.7, 6.2, -2.5, 1.3)
        add(0, 6.55, -3.0, 1.3)
        add(1.7, 6.2, -2.5, 1.4)
        add(2.25, 5.05, -1.0, 1.5)
        add(1.65 * broad, 1.5, 0, 1.85)
        var previous: TieMove.Region = .R
        var crossings: [Crossing] = []
        for (index, move) in moves.enumerated() {
            let finalFacade = index == moves.count - 2
            let progress = Double(index) / Double(moves.count - 1)
            let depth = move.inward ? 0.45 + progress * 0.95 : -0.50 - progress * 0.30
            let radius = (1.58 + progress * 0.20) * broad
            let y = 0.90 - progress * 0.85
            var middle: V3
            let destination: V3
            if move.region == .C {
                let side = previous == .L ? -1.0 : 1.0
                middle = V3(side * 1.02 * broad, 1.65, depth)
                destination = V3(side * 0.15, 2.55, depth * 0.5)
            } else if previous == .C {
                let side = move.region == .L ? -1.0 : 1.0
                middle = V3(side * 1.05 * broad, 1.65, depth)
                destination = V3(side * radius, y, 0)
            } else {
                middle = V3(kind == .fourInHand ? -0.18 : 0, y, depth)
                destination = V3(move.region == .L ? -radius : radius, y + 0.02, 0)
            }
            let width = finalFacade ? 2.6 * broad : 1.85 + progress * 0.45
            if finalFacade { middle.z = 1.45; middle.y = 0.28 }
            add(middle.x, middle.y, middle.z, width, index)
            crossings.append(Crossing(token: move.token, anchor: middle, moveIndex: index))
            add(destination.x, destination.y, destination.z, finalFacade ? 1.95 : width, index)
            previous = move.region
        }
        // T: cross in front of the neck loop, over the top of the active loop,
        // then behind its facade and emerge beneath it. Kept as a visible route
        // in inspection mode; not a topology certificate or a contact solution.
        let tuck = moves.count
        let lean = kind == .fourInHand ? -0.23 : 0.0
        add(lean, 2.15, 1.80, 2.05, tuck)
        add(lean, 1.2, 0.70, 2.10, tuck)
        add(lean, 0.0, 0.32, 2.25, tuck)
        add(lean, -1.55, 0.75, 2.65, tuck)
        add(lean * 0.6, -5.3, 0.9, 3.8, tuck)
        add(0, -12.8, 1.0, 6.05, tuck)
        add(0, -14.5, 1.0, 6.5, tuck)
        add(0, -17.5, 1.0, 0.035, tuck)
        var dense: [(V3, Double, Int, Double)] = []
        for i in 0..<(points.count - 1) {
            let a = points[max(0, i - 1)], b = points[i], c = points[i + 1], d = points[min(points.count - 1, i + 2)]
            let count = max(18, Int(simd_length(c.p - b.p) * 12))
            for j in 0..<count {
                let t = Double(j) / Double(count), t2 = t*t, t3 = t2*t
                // Uniform Catmull-Rom, with width interpolated monotonically to avoid edge inversion.
                func component(_ index: Int) -> Double {
                    let x0 = a.p[index], x1 = b.p[index], x2 = c.p[index], x3 = d.p[index]
                    let linear = (x2-x0)*t
                    let quadratic = (2*x0-5*x1+4*x2-x3)*t2
                    let cubic = (-x0+3*x1-3*x2+x3)*t3
                    return (2*x1+linear+quadratic+cubic)*0.5
                }
                let p = V3(component(0), component(1), component(2))
                let ease = t*t*(3-2*t)
                let startRoll = kind == .pratt && b.phase < 1 ? Double.pi : 0
                let endRoll = kind == .pratt && c.phase < 1 ? Double.pi : 0
                dense.append((p, b.width+(c.width-b.width)*ease, c.phase, startRoll+(endRoll-startRoll)*ease))
            }
        }
        dense.append((points.last!.p, points.last!.width, tuck, 0))
        var samples: [RibbonSample] = []
        var distance = 0.0
        var across = V3(1,0,0)
        for i in dense.indices {
            if i > 0 { distance += simd_length(dense[i].0-dense[i-1].0) }
            let tangent = unit(dense[min(i+1,dense.count-1)].0-dense[max(0,i-1)].0)
            // Transport the material frame; use the diagram plane as a soft guide.
            // The sign-continuity constraint prevents abrupt U flips at turns.
            let projected = across - tangent * simd_dot(across,tangent)
            var candidate = unit(simd_cross(tangent,V3(0,0,1)))
            if simd_dot(candidate,projected) < 0 { candidate = -candidate }
            let guideWeight = 0.05 * simd_length(simd_cross(tangent,V3(0,0,1)))
            across = unit(candidate * guideWeight + unit(projected) * (1-guideWeight))
            // Pratt starts back-out. Its first neck loop carries an authored half twist.
            // This explicit material-frame assumption is not inferred from topology.
            let roll = dense[i].3
            let materialAcross = across*cos(roll)+simd_cross(tangent,across)*sin(roll)
            let normal = unit(simd_cross(materialAcross,tangent))
            samples.append(RibbonSample(center:dense[i].0, across:materialAcross, normal:normal, width:dense[i].1,s:distance,phase:dense[i].2))
        }
        // FM words do not determine ribbon framing. Use explicit broad-face
        // constraints at each authored crossing; interpolate roll along the
        // transported frame, retaining the same continuous widthwise coordinate.
        var constraints: [(Int, Double)] = []
        func constrain(_ index: Int, normal: V3) {
            let tangent = unit(dense[min(index+1,dense.count-1)].0-dense[max(0,index-1)].0)
            let target = unit(simd_cross(tangent,normal))
            let actual = samples[index].across
            var roll = atan2(simd_dot(tangent,simd_cross(actual,target)),simd_dot(actual,target))
            if let last = constraints.last {
                while roll-last.1 > .pi { roll -= 2 * .pi }
                while roll-last.1 < -.pi { roll += 2 * .pi }
            }
            constraints.append((index,roll))
        }
        constrain(0,normal:V3(0,0,kind.sequence.undersideAtNeck ? -1 : 1))
        let neckEnd = samples.firstIndex(where: { $0.phase == 0 })!
        constrain(neckEnd,normal:V3(0,0,kind.sequence.undersideAtNeck ? -1 : 1))
        for crossing in crossings {
            let index = samples.indices.min(by: { simd_distance(samples[$0].center,crossing.anchor) < simd_distance(samples[$1].center,crossing.anchor) })!
            constrain(index,normal:V3(0,0,moves[crossing.moveIndex].inward ? 1 : -1))
        }
        let bladeStart = samples.firstIndex(where: { $0.phase == moves.count && $0.center.y < -1.4 })!
        constrain(bladeStart,normal:V3(0,0,1))
        constrain(samples.count-1,normal:V3(0,0,1))
        var segment = 0
        for i in samples.indices {
            while segment+1 < constraints.count-1 && i > constraints[segment+1].0 { segment += 1 }
            let a = constraints[segment], b = constraints[segment+1]
            let fraction = min(1,max(0,(samples[i].s-samples[a.0].s)/(samples[b.0].s-samples[a.0].s)))
            let roll = a.1+(b.1-a.1)*fraction*fraction*(3-2*fraction)
            let tangent = unit(dense[min(i+1,dense.count-1)].0-dense[max(0,i-1)].0)
            let old = samples[i].across
            samples[i].across = old*cos(roll)+simd_cross(tangent,old)*sin(roll)
            samples[i].normal = unit(simd_cross(samples[i].across,tangent))
        }
        return RibbonModel(kind:kind,samples:samples,crossings:crossings)
    }

    static func position(_ sample: RibbonSample, transverse: Double, spread: Double) -> V3 {
        // Spread is an inspection deformation of the canonical material; s never changes.
        var p = sample.center
        if sample.phase >= 0 && sample.center.y > -2 {
            let fade = min(1, max(0, (sample.center.y+2)/2))
            p.z += spread * fade * (Double(sample.phase) * 0.58 - 1.0)
            p.x *= 1 + spread * 0.13 * fade
        }
        return p + sample.across * transverse
    }
    static func uv(transverse: Double, s: Double, repeatCM: Double, offsetCM: Double, angle: Double, aspect: Double = 1) -> SIMD2<Double> {
        let c = cos(angle), n = sin(angle)
        // Looking at the flat front, +s runs from narrow to wide tip (down)
        // and -transverse points right. SceneKit image V=0 is the image top.
        // The central fabric line samples the horizontal center of the tile.
        let right = -transverse
        return SIMD2(0.5+(right*c-(s+offsetCM)*n)/repeatCM, (right*n+(s+offsetCM)*c)/(repeatCM*aspect))
    }
}
