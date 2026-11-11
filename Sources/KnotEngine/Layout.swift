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
    /// Thickness of the cloth relative to an ordinary silk twill (1). Thicker
    /// cloth makes every layer, fold and wrap bulkier, so the same sequence
    /// ties a bigger knot.
    var weight = 1.0
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
    /// How strongly the knot narrows toward the bottom on each side.
    var taperLeft = 0.16
    var taperRight = 0.16
    /// The chord the tuck passes under, when the knot is finished.
    var bandChord: Int?

    static func restProgress(moves: Int, lastIsCenter: Bool, tuck: Bool) -> Double {
        if moves == 0 { return 0 }
        if tuck { return Double(2 * moves + 1) }
        return Double(lastIsCenter ? 2 * moves : 2 * moves - 1)
    }

    /// - Parameters:
    ///   - dress: 0 while tying (the open, diagram-like layout); 1 once the knot
    ///     is tucked and pulled snug. Dressing is what tension does to a
    ///     finished knot, expressed as where each fold ends up when it has been
    ///     drawn in as far as the cloth under it allows.
    ///   - bandWidth: visible width of the front band, cm.
    ///   - layer: spacing between layers, cm (for the size of the top roll).
    static func make(_ program: KnotProgram, scale sc: Double, dress: Double = 0,
                     bandWidth: Double = 3.9, layer: Double = 0.15, weight: Double = 1) -> Layout {
        var lay = Layout()
        lay.mirrored = program.moves.first?.region == .R
        lay.insideOut = program.moves.first.map { !$0.inward } ?? false
        lay.tucked = program.tuck
        let moves = lay.mirrored
            ? program.moves.map { Move(region: $0.region.mirrored, inward: $0.inward) }
            : program.moves
        let centers = moves.filter { $0.region == .C }.count
        lay.strandX = (0.95 + 0.20 * weight + 0.10 * weight * Double(min(centers, 3))) * sc
        lay.strandY = 0.35 * sc
        lay.points = [V2(lay.strandX, lay.strandY)]
        lay.caps = [2.1]
        for move in moves { lay.sides.append(move.inward ? 1 : -1) }

        // Stacking order: every chord lies outside the earlier ones on its side.
        var front = 0.0, back = 0.0
        for side in lay.sides {
            if side > 0 { front += 1; lay.depths.append(front) } else { back += 1; lay.depths.append(back) }
        }
        let band = program.tuck ? KnotProgram.tuckBand(moves) : nil
        lay.bandChord = band
        let dressed = band == nil ? 0 : clamp01(dress)

        // How far the front band has to reach up to cover the folds over the top
        // once the centre passes have been drawn down onto the crossing.
        var bandY = -1.52
        if let band {
            let last = Double(max(centers - 1, 0))
            let roll = min(0.5 * layer * (lay.depths[band] + (lay.depths.last ?? 1) + 2), WoundPath.foldBulge * layer)
            let cover = (0.28 + 0.15 * weight * last) * sc + roll + 0.22
            // Never above the crossing, or the band would wrap the neck strands.
            bandY = min(-1.02, max(-1.52, (cover - bandWidth / 2) / sc))
        }

        var visitsL = 0, visitsR = 0, visitsC = 0
        var lowest = 0.0, widest = moves.isEmpty ? 1.45 : 0.0, highest = 0.35
        for (index, move) in moves.enumerated() {
            let onBand = band.map { index == $0 || index == $0 - 1 } ?? false
            switch move.region {
            case .L, .R:
                let left = move.region == .L
                let visit = Double(left ? visitsL : visitsR)
                let x = 1.25 + (0.20 + 0.26 * visit) * weight
                let open = (left ? -1.52 : -1.58) - 0.12 * visit
                // Dressed, the inner wraps are drawn up level with the band and
                // gathered so that they hide behind it.
                let snug = bandY - (left ? 0 : 0.05) + (onBand ? 0 : 0.06)
                let y = mix(open, snug, dressed)
                lay.points.append(V2(left ? -x : x, y) * sc)
                let cap = 4.0 + 0.15 * visit
                lay.caps.append(onBand ? cap : mix(cap, min(cap, bandWidth - 0.5), dressed))
                lowest = min(lowest, y); widest = max(widest, x)
                if left { visitsL += 1 } else { visitsR += 1 }
            case .C:
                let visit = Double(visitsC)
                let y = mix(0.50 + 0.20 * weight * visit, 0.28 + 0.15 * weight * visit, dressed)
                lay.points.append(V2(0, y) * sc)
                lay.caps.append(2.5)
                highest = max(highest, y)
                visitsC += 1
            }
        }
        if moves.isEmpty { lowest = -1.52 }
        lay.halfWidth = widest * sc
        lay.yBottom = lowest * sc - mix(2.1, bandWidth / 2 + 0.1, dressed)
        lay.yTop = mix(highest * sc + 0.25, bandY * sc + bandWidth / 2, dressed)
        let exit = V2(0, lay.yBottom - 0.5)

        // Shoulders: every pass around a neck strand adds bulk at that top
        // corner, so the dressed knot widens upward on that side.
        var aroundLeft = 0.0, aroundRight = 0.0
        if moves.count > 1 {
            for j in 1..<moves.count {
                let pair: Set<Region> = [moves[j - 1].region, moves[j].region]
                if pair == [.L, .C] { aroundLeft += 1 } else if pair == [.R, .C] { aroundRight += 1 }
            }
        }
        let bulk = 0.15 + 0.05 * (aroundLeft + aroundRight)
        lay.taperLeft = mix(0.16, min(0.45, bulk + 0.035 * (aroundLeft - aroundRight)), dressed)
        lay.taperRight = mix(0.16, min(0.45, bulk + 0.035 * (aroundRight - aroundLeft)), dressed)

        let lastIsCenter = moves.last?.region == .C
        if let band {
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
        taperLeft = mix(taperLeft, target.taperLeft, rate); taperRight = mix(taperRight, target.taperRight, rate)
        bandChord = target.bandChord
    }

    func distance(to target: Layout) -> Double {
        var d = abs(yBottom - target.yBottom) + abs(strandX - target.strandX) + abs(halfWidth - target.halfWidth)
        for i in points.indices where i < target.points.count { d = max(d, simd_distance(points[i], target.points[i])) }
        for i in depths.indices where i < target.depths.count { d = max(d, abs(depths[i] - target.depths[i])) }
        return d
    }
}
