import Foundation
import simd

struct KnotParams: Equatable {
    /// 0 = loose and open, 1 = pulled snug.
    var tightness = 0.85
    /// Multiplies the spacing between layers; an inspection aid.
    var layerSpread = 1.0
    /// Choose the narrow end's length so the finished knot leaves the wide end
    /// hanging a little lower than the narrow one, as you would when dressing.
    var autoBalance = true
    /// Length of the narrow end hanging below the knot, cm (when not balancing).
    var narrowEnd = 38.0
    /// Tying speed multiplier.
    var speed = 1.0
}

/// The knot reduced to what the notation actually specifies: a ribbon wound
/// around a flat core. Each move is one straight chord across the front or the
/// back, ending at a fold on the left edge, the right edge or over the top.
/// Later chords always lie outside earlier ones, so the stacking order is known
/// in advance and no collision detection is needed.
///
/// Everything is in the canonical (first move to the left) orientation; a
/// sequence that starts to the right is built mirrored.
struct Layout {
    /// points[0] is where the wide end leaves the right neck strand; one fold
    /// point per move follows, then the exit below the knot (tuck) or a
    /// virtual point that only gives the last fold its direction.
    var points: [V2] = []
    /// +1 front, −1 back, one per chord.
    var sides: [Double] = []
    /// Stacking depth per chord, in layers from the core.
    var depths: [Double] = []
    /// Visible width cap at each point.
    var caps: [Double] = []
    var restProgress = 0.0
    var mirrored = false
    var insideOut = false
    var tucked = false
    var strandX = 1.15
    var strandY = 0.35
    var yBottom = -3.9
    var yTop = 0.6
    var halfWidth = 1.5

    static func restProgress(moves: Int, lastIsCenter: Bool, tuck: Bool) -> Double {
        if moves == 0 { return 0 }
        if tuck { return Double(2 * moves + 1) }
        return Double(lastIsCenter ? 2 * moves : 2 * moves - 1)
    }

    static func make(_ program: KnotProgram, scale sc: Double) -> Layout {
        var lay = Layout()
        lay.mirrored = program.moves.first?.region == .R
        lay.insideOut = program.moves.first.map { !$0.inward } ?? false
        lay.tucked = program.tuck
        let moves = lay.mirrored
            ? program.moves.map { Move(region: $0.region.mirrored, inward: $0.inward) }
            : program.moves
        let centers = moves.filter { $0.region == .C }.count
        lay.strandX = (1.15 + 0.10 * Double(min(centers, 3))) * sc
        lay.strandY = 0.35 * sc
        lay.points = [V2(lay.strandX, lay.strandY)]
        lay.caps = [2.1]

        var visitsL = 0, visitsR = 0, visitsC = 0
        var lowest = -1.52, widest = 1.45, highest = 0.35
        for move in moves {
            switch move.region {
            case .L:
                let x = 1.45 + 0.26 * Double(visitsL), y = -1.52 - 0.12 * Double(visitsL)
                lay.points.append(V2(-x, y) * sc)
                lay.caps.append(4.0 + 0.15 * Double(visitsL))
                lowest = min(lowest, y); widest = max(widest, x)
                visitsL += 1
            case .R:
                let x = 1.45 + 0.26 * Double(visitsR), y = -1.58 - 0.12 * Double(visitsR)
                lay.points.append(V2(x, y) * sc)
                lay.caps.append(4.0 + 0.15 * Double(visitsR))
                lowest = min(lowest, y); widest = max(widest, x)
                visitsR += 1
            case .C:
                let y = 0.50 + 0.20 * Double(visitsC)
                lay.points.append(V2(0, y) * sc)
                lay.caps.append(2.5)
                highest = max(highest, y)
                visitsC += 1
            }
            lay.sides.append(move.inward ? 1 : -1)
        }
        lay.halfWidth = widest * sc
        lay.yBottom = lowest * sc - 2.1
        lay.yTop = highest * sc + 0.25
        let exit = V2(0, lay.yBottom - 0.5)

        // Stacking order: every chord lies outside the earlier ones on its side.
        var front = 0.0, back = 0.0
        for side in lay.sides {
            if side > 0 { front += 1; lay.depths.append(front) } else { back += 1; lay.depths.append(back) }
        }
        let lastIsCenter = moves.last?.region == .C
        if program.tuck, let band = KnotProgram.tuckBand(moves) {
            // The tuck slides under the last front band: it takes that band's
            // depth, and the band (with anything laid over it) moves out by one.
            let under = lay.depths[band]
            for k in band..<lay.sides.count where lay.sides[k] > 0 { lay.depths[k] += 1 }
            lay.points.append(exit); lay.caps.append(3.2)
            lay.sides.append(1); lay.depths.append(under)
        } else if lastIsCenter, let side = lay.sides.last {
            // The wide end has gone over the top and hangs on the other side.
            lay.points.append(exit); lay.caps.append(3.2)
            lay.sides.append(-side)
            lay.depths.append((side > 0 ? back : front) + 1)
        }
        lay.restProgress = restProgress(moves: moves.count, lastIsCenter: lastIsCenter, tuck: program.tuck)
        return lay
    }

    /// Move the continuous quantities toward `target`; discrete ones switch.
    mutating func ease(toward target: Layout, rate: Double) {
        func resize<T>(_ current: inout [T], _ goal: [T]) {
            if current.count > goal.count { current.removeLast(current.count - goal.count) }
            while current.count < goal.count { current.append(goal[current.count]) }
        }
        resize(&points, target.points); resize(&depths, target.depths); resize(&caps, target.caps)
        for i in points.indices { points[i] = mix(points[i], target.points[i], rate) }
        for i in depths.indices { depths[i] = mix(depths[i], target.depths[i], rate) }
        for i in caps.indices { caps[i] = mix(caps[i], target.caps[i], rate) }
        sides = target.sides
        restProgress = target.restProgress
        mirrored = target.mirrored; insideOut = target.insideOut; tucked = target.tucked
        strandX = mix(strandX, target.strandX, rate); strandY = mix(strandY, target.strandY, rate)
        yBottom = mix(yBottom, target.yBottom, rate); yTop = mix(yTop, target.yTop, rate)
        halfWidth = mix(halfWidth, target.halfWidth, rate)
    }

    func distance(to target: Layout) -> Double {
        var d = abs(yBottom - target.yBottom) + abs(strandX - target.strandX) + abs(halfWidth - target.halfWidth)
        for i in points.indices where i < target.points.count { d = max(d, simd_distance(points[i], target.points[i])) }
        for i in depths.indices where i < target.depths.count { d = max(d, abs(depths[i] - target.depths[i])) }
        return d
    }
}

/// The wound part of the tie as an exact piecewise curve: straight chords in
/// the layer planes joined by helical rolls around the fold lines.
struct WoundPath {
    struct Frame {
        var p = V3.zero, t = V3(0, -1, 0), a = V3(-1, 0, 0), n = V3(0, 0, 1)
        var kappa = 0.0
        var cap = 2.1
    }
    struct Chord {
        var start: V2, end: V2
        var dir = V2(1, 0)
        var len = 0.0
        var side: Double, z: Double
        var k0 = 0.0, k1 = 0.0
        var cap0: Double, cap1: Double
    }
    struct Roll {
        var q = V2.zero, e = V2(0, 1), o = V2(1, 0)
        var cosT = 0.0, sinT = 1.0
        var r = 0.1, zMid = 0.0, sideIn = 1.0
        var len = 0.3
        var k0 = 0.0, k1 = 0.0
        var cap = 2.5
        /// Whether the fold wraps over the top (a centre fold) rather than a side.
        var overTop = false
    }
    var chords: [Chord] = []
    var rolls: [Roll] = []

    var pieceCount: Int { max(0, 2 * chords.count - 1) }
    func pieceLength(_ piece: Int) -> Double {
        piece % 2 == 0 ? chords[piece / 2].len : rolls[piece / 2].len
    }
    func length(upTo progress: Double) -> Double {
        var total = 0.0
        let whole = min(Int(progress), pieceCount)
        for i in 0..<whole { total += pieceLength(i) }
        if whole < pieceCount { total += (progress - Double(whole)) * pieceLength(whole) }
        return total
    }

    init() {}

    init(layout lay: Layout, layer: Double) {
        let m = lay.sides.count
        guard m > 0, lay.points.count == m + 1 else { return }
        for j in 0..<m {
            chords.append(Chord(start: lay.points[j], end: lay.points[j + 1], side: lay.sides[j],
                                z: lay.sides[j] * (lay.depths[j] + 0.5) * layer,
                                cap0: lay.caps[j], cap1: lay.caps[j + 1]))
        }
        rolls = Array(repeating: Roll(), count: max(0, m - 1))
        func refresh() {
            for j in 0..<m {
                let d = chords[j].end - chords[j].start
                chords[j].len = max(simd_length(d), 1e-3)
                chords[j].dir = d / chords[j].len
            }
        }
        // A flat fold reflects the ribbon about the fold line, so the line is the
        // bisector of the two chord directions. Around a roll of radius r the
        // centreline is a helix that advances along the fold line; the chord
        // ends shift accordingly, hence the short fixed-point loop.
        for pass in 0..<24 {
            refresh()
            var moved = 0.0
            for j in 0..<(m - 1) {
                let tin = chords[j].dir, tout = chords[j + 1].dir
                var e = tin + tout
                if simd_length(e) < 1e-4 { e = V2(-tin.y, tin.x) }
                e = unit(e)
                var o = V2(-e.y, e.x)
                if simd_dot(o, tin) < 0 { o = -o }
                var sinT = simd_dot(o, tin), cosT = simd_dot(e, tin)
                if sinT < 0.35 { sinT = 0.35; cosT = (cosT < 0 ? -1 : 1) * (1 - 0.35 * 0.35).squareRoot() }
                let r = max(0.03, abs(chords[j].z - chords[j + 1].z) / 2)
                let advance = Double.pi * r * cosT / sinT
                let pivot = lay.points[j + 1]
                var roll = Roll()
                roll.q = pivot - e * (advance / 2)
                roll.e = e; roll.o = o; roll.cosT = cosT; roll.sinT = sinT; roll.r = r
                roll.zMid = (chords[j].z + chords[j + 1].z) / 2
                roll.sideIn = chords[j].side
                roll.len = Double.pi * r / sinT
                roll.cap = lay.caps[j + 1]
                roll.overTop = abs(e.x) > abs(e.y)
                rolls[j] = roll
                // Under-relaxed so thick knots, whose rolls are large next to
                // their chords, settle instead of oscillating.
                let relax = pass == 0 ? 1.0 : 0.6
                let end = mix(chords[j].end, roll.q, relax), start = mix(chords[j + 1].start, roll.q + e * advance, relax)
                moved = max(moved, simd_distance(end, chords[j].end), simd_distance(start, chords[j + 1].start))
                chords[j].end = end
                chords[j + 1].start = start
            }
            if moved < 1e-5 { break }
        }
        refresh()
        // Make the pieces meet exactly, whatever the loop left over.
        for j in 0..<(m - 1) {
            let advance = Double.pi * rolls[j].r * rolls[j].cosT / rolls[j].sinT
            rolls[j].q = chords[j].end
            chords[j + 1].start = chords[j].end + rolls[j].e * advance
        }
        refresh()
        // Shear of the rulings so that rows lie along the fold lines.
        for j in 0..<(m - 1) {
            let e = rolls[j].e
            func slope(_ c: Chord) -> Double {
                let across = V2(c.dir.y, -c.dir.x) * c.side
                var den = simd_dot(e, across)
                if abs(den) < 0.35 { den = den < 0 ? -0.35 : 0.35 }
                return simd_dot(e, c.dir) / den
            }
            chords[j].k1 = slope(chords[j])
            chords[j + 1].k0 = slope(chords[j + 1])
        }
        // Keep neighbouring rulings from crossing inside the ribbon.
        for j in 0..<m {
            let change = abs(chords[j].k1 - chords[j].k0)
            let width = max(chords[j].cap0, chords[j].cap1)
            let limit = 1.5 * chords[j].len / max(width, 0.5)
            if change > limit { let f = limit / change; chords[j].k0 *= f; chords[j].k1 *= f }
        }
        for j in 0..<(m - 1) { rolls[j].k0 = chords[j].k1; rolls[j].k1 = chords[j + 1].k0 }
    }

    func eval(piece: Int, frac f: Double) -> Frame {
        var frame = Frame()
        if piece % 2 == 0 {
            let c = chords[piece / 2]
            frame.p = v3(c.start + c.dir * (c.len * f), c.z)
            frame.t = V3(c.dir.x, c.dir.y, 0)
            frame.n = V3(0, 0, c.side)
            frame.a = simd_cross(frame.t, frame.n)
            frame.kappa = mix(c.k0, c.k1, f)
            frame.cap = mix(c.cap0, c.cap1, smoothstep(0, 1, f))
        } else {
            let r = rolls[piece / 2]
            let phi = Double.pi * f
            let e = V3(r.e.x, r.e.y, 0), o = V3(r.o.x, r.o.y, 0), z = V3(0, 0, 1)
            let along = r.r * phi * r.cosT / r.sinT
            frame.p = v3(r.q, r.zMid + r.r * r.sideIn * cos(phi)) + e * along + o * (r.r * sin(phi))
            frame.t = unit(e * r.cosT + (o * cos(phi) - z * (r.sideIn * sin(phi))) * r.sinT)
            frame.n = z * (r.sideIn * cos(phi)) + o * sin(phi)
            frame.a = simd_cross(frame.t, frame.n)
            frame.kappa = mix(r.k0, r.k1, f)
            frame.cap = r.cap
        }
        return frame
    }

    /// Frame at a progress value measured in pieces.
    func eval(progress: Double) -> Frame {
        guard pieceCount > 0 else { return Frame() }
        let clamped = min(max(progress, 0), Double(pieceCount))
        let piece = min(Int(clamped), pieceCount - 1)
        return eval(piece: piece, frac: clamped - Double(piece))
    }
}
