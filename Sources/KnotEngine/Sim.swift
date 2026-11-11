import Foundation
import simd

/// Real-time tie model.
///
/// Three parts, cheapest first:
///  1. the narrow end and neck loop are a fixed spline;
///  2. the wound part is the exact folded path given by the notation
///     (`WoundPath`), revealed up to `progress`;
///  3. the free wide end is a short chain of particles that hangs, swings and
///     is carried around the knot as moves are added or removed.
/// The whole thing is re-meshed every step; a step costs well under a
/// millisecond, so it runs at display rate with a large margin.
final class KnotSim {
    var params = KnotParams()
    /// The knot to show. Change it at any time; the model ties or unties
    /// itself step by step to get there.
    var goal = KnotProgram()
    /// The complete knot being worked toward, when `goal` is only part of it.
    /// The two ends are balanced for this knot, so they stay put while stepping
    /// through it.
    var fullProgram: KnotProgram?

    private(set) var shown = KnotProgram()
    private(set) var progress = 0.0
    private(set) var target = 0.0
    private(set) var isMoving = true
    private(set) var rows: [Row] = []
    let mesh = RibbonMesh()
    private(set) var shape = RibbonMesh.Shape()
    /// Material coordinate where the wide end leaves the knot, and its length.
    private(set) var anchorS = 0.0
    /// Material coordinate where the neck loop ends and the winding starts.
    private(set) var woundStartS = 0.0
    var freeLength: Double { max(0, TieBlank.length - anchorS) }
    /// Lowest point of the wide end and of the narrow end (y, cm).
    private(set) var wideTipY = 0.0
    private(set) var narrowTipY = 0.0
    var knotCenterY: Double { (lay.yTop + lay.yBottom) / 2 }

    private var lay = Layout.make(KnotProgram(), scale: 1)
    private var path = WoundPath()
    private var anchor = WoundPath.Frame()
    private var cross = 0.0
    private var loose = 0.15
    private var spread = 1.0
    private var tuckAmount = 0.0
    private var narrow = 38.0
    private var lead = 0.0
    private var dress = 0.0
    private var weight = 1.0
    /// Threading the tuck: length of the bight still hanging in front of the
    /// band, or nil when the wide end is not being fed through.
    private var threadLoop: Double?
    private var snapTail = false
    private(set) var neck = NeckRing()
    /// 0 = collar standing up (while tying), 1 = folded down over the tie.
    private(set) var collarFold = 0.0
    private var bandWidth = 3.9
    private var fixedLength = 47.0
    /// Current length of the narrow end below the knot, cm.
    var narrowEnd: Double { narrow }
    private var started = false
    private var layer = 0.2

    // Free end: particles one centimetre apart, index 0 at the wide tip.
    private let seg = 1.0
    private var tp: [V3] = []
    private var tq: [V3] = []
    private var pose: [V3] = []
    private var active = 0
    private var tailSpeed = 0.0
    private var shirtZ = -1.0
    private var planeNormal = V3(0, 0, 1)
    private var chain: [V3] = []
    private var chainS: [Double] = []

    init() {
        let count = Int(TieBlank.length / seg) + 2
        tp = Array(repeating: .zero, count: count)
        tq = tp
        pose = tp
    }

    /// Free-end particles from the knot outward (for checks and debugging).
    var tailPoints: [V3] { (0..<active).reversed().map { pose[$0] } }
    var anchorFrame: WoundPath.Frame { anchor }
    var layout: Layout { lay }
    var woundPath: WoundPath { path }

    // MARK: Stepping

    /// Jump straight to the goal and let the free end come to rest.
    func settle(seconds: Double = 3) {
        shown = goal
        started = false
        step(1.0 / 60)
        var time = 0.0
        while time < seconds && (isMoving || time < 0.3) { step(1.0 / 60); time += 1.0 / 60 }
    }

    func step(_ dtIn: Double) {
        let dt = min(max(dtIn, 1.0 / 240), 1.0 / 30)
        let retracting = reconcile()
        let rate = started ? 1 - exp(-dt / 0.09) : 1
        loose = mix(loose, 1 - min(1, max(0, params.tightness)), rate)
        spread = mix(spread, params.layerSpread, rate)
        let scale = 1 + 0.55 * loose
        weight = mix(weight, min(2, max(0.5, params.weight)), rate)
        layer = (0.15 * weight + 0.45 * loose) * spread
        // Dressing: once the tuck is through, the knot is drawn snug. Loosening
        // it with the tightness control opens it back up to show its structure.
        let through = shown.tuck && progress > Double(2 * shown.moves.count) + 0.9
        let dressGoal = through ? smoothstep(0.35, 0.75, 1 - loose) : 0.0
        dress = started ? mix(dress, dressGoal, 1 - exp(-dt / 0.30)) : (shown.tuck ? smoothstep(0.35, 0.75, 1 - loose) : 0)
        let goalLayout = Layout.make(shown, scale: scale, dress: dress, bandWidth: bandWidth, layer: layer, weight: weight)
        if started { lay.ease(toward: goalLayout, rate: rate) } else { lay = goalLayout }
        let crossGoal = shown.moves.isEmpty ? 0.0 : 1.0
        cross = started ? mix(cross, crossGoal, 1 - exp(-dt / 0.16)) : crossGoal
        path = WoundPath(layout: lay, layer: layer)
        var narrowGoal = params.narrowEnd
        if params.autoBalance {
            let fullLayout = Layout.make(fullProgram ?? goal, scale: scale, dress: dress, bandWidth: bandWidth, layer: layer, weight: weight)
            let wound = WoundPath(layout: fullLayout, layer: layer).length(upTo: fullLayout.restProgress)
            narrowGoal = (TieBlank.length - fixedLength - wound - 5) / 2
        }
        narrowGoal = min(60, max(14, narrowGoal))
        narrow = mix(narrow, narrowGoal, rate)
        if !retracting { target = lay.restProgress }
        target = min(target, Double(path.pieceCount))
        if started { advanceOrThread(dt) } else { progress = target; threadLoop = nil }
        // Dressed, the knot is drawn up to the collar and the collar comes down.
        neck.yFront = mix(3.6, 1.7, dress)
        neck.zc = -neck.rz - 1.6
        let foldGoal = dress > 0.6 ? 1.0 : 0.0
        collarFold = started ? min(1, max(0, collarFold + (foldGoal > collarFold ? 1 : -1) * dt / 0.6)) : foldGoal
        if abs(collarFold - foldGoal) < dt / 0.6 { collarFold = foldGoal }
        let leadGoal = abs(progress - target) > 1e-6 ? 1.0 : 0.0
        lead = started ? mix(lead, leadGoal, 1 - exp(-dt / (leadGoal > lead ? 0.12 : 0.28))) : 0
        let tuckGoal = shown.tuck && progress > Double(2 * shown.moves.count) + 0.5 ? 1.0 : 0.0
        tuckAmount = mix(tuckAmount, tuckGoal, rate)

        rows.removeAll(keepingCapacity: true)
        let end = buildStatic(scale: scale)
        buildWound(from: end)
        let previous = active
        active = max(0, Int(((TieBlank.length - anchorS - 0.02) / seg).rounded(.up)))
        active = min(active, tp.count)
        if !started || snapTail { resetTail(); snapTail = false } else if active > previous {
            for i in previous..<active { tp[i] = anchor.p; tq[i] = anchor.p }
        }
        if threadLoop != nil { buildThread() } else {
            stepTail(started ? dt : 0)
            poseTail()
            buildTail()
        }

        shape.yCenter = (lay.yTop + lay.yBottom) / 2
        shape.radiusX = lay.halfWidth + 1.3
        shape.radiusY = (lay.yTop - lay.yBottom) / 2 + 0.9
        shape.bulge = (1.0 + 0.25 * weight) * cross
        mesh.thickness = weight
        shape.taperLeft = lay.taperLeft * cross
        shape.taperRight = lay.taperRight * cross
        shape.mirror = lay.mirrored
        mesh.build(rows: rows, shape: shape)

        let easing = lay.distance(to: goalLayout) > 2e-3 || abs(cross - crossGoal) > 2e-3
            || abs(loose - (1 - params.tightness)) > 2e-3 || abs(spread - params.layerSpread) > 2e-3
            || abs(tuckAmount - tuckGoal) > 2e-3 || abs(narrow - narrowGoal) > 2e-3 || lead > 2e-3
            || abs(dress - dressGoal) > 2e-3 || abs(weight - params.weight) > 2e-3
            || threadLoop != nil || collarFold != foldGoal
        isMoving = !started || easing || abs(progress - target) > 1e-6 || shown != goal || tailSpeed > 0.6
        started = true
    }

    /// Brings `shown` one notch closer to `goal`. Returns true while the wide
    /// end still has to be unwound before `shown` can change.
    private func reconcile() -> Bool {
        if shown == goal { return false }
        let count = shown.moves.count
        if shown.tuck && !(goal.tuck && goal.moves == shown.moves) {
            target = Double(2 * count)
            if progress > target + 1e-6 || threadLoop != nil { return true }
            shown.tuck = false
        }
        var common = 0
        while common < min(shown.moves.count, goal.moves.count) && shown.moves[common] == goal.moves[common] { common += 1 }
        if shown.moves.count > common {
            let center = common > 0 && shown.moves[common - 1].region == .C
            target = Layout.restProgress(moves: common, lastIsCenter: center, tuck: false)
            if progress > target + 1e-6 { return true }
            shown.moves.removeLast(shown.moves.count - common)
        }
        shown = goal
        return false
    }

    /// Moves along the wound path, except for the tuck: that last chord is not
    /// laid down from the top. The wide end is lifted, its tip is fed under the
    /// band, and the cloth is drawn through until the bight in front is gone.
    private func advanceOrThread(_ dt: Double) {
        let folded = Double(2 * shown.moves.count)
        guard shown.tuck, path.pieceCount == 2 * shown.moves.count + 1 else {
            threadLoop = nil
            advance(dt, to: target)
            return
        }
        let free = freeLength
        let speed = 22 * params.speed
        if target > folded {
            if progress < folded - 1e-9 { advance(dt, to: folded); return }
            if progress >= folded + 1 - 1e-9 { return }
            progress = folded
            let loop = (threadLoop ?? free) - speed * dt
            if loop <= 0 { threadLoop = nil; progress = folded + 1; snapTail = true } else { threadLoop = loop }
        } else if progress > folded + 1e-9 || threadLoop != nil {
            progress = folded
            let loop = (threadLoop ?? 0) + speed * dt
            threadLoop = loop >= free ? nil : loop
            if threadLoop == nil { snapTail = true }
        } else {
            advance(dt, to: target)
        }
    }

    private func advance(_ dt: Double, to target: Double) {
        guard path.pieceCount > 0 else { progress = 0; return }
        var time = dt
        var guardCount = 0
        while time > 1e-9 && abs(target - progress) > 1e-9 && guardCount < 64 {
            guardCount += 1
            let forward = target > progress
            var piece = forward ? Int(progress + 1e-9) : Int((progress - 1e-9).rounded(.up)) - 1
            piece = min(max(piece, 0), path.pieceCount - 1)
            let length = max(path.pieceLength(piece), 1e-3)
            var speed = 14 * params.speed
            if piece % 2 == 1 {
                // A fold swings the whole free end around; give it time to read.
                let duration = (path.rolls[piece / 2].overTop ? 0.70 : 0.45) / max(params.speed, 0.1)
                speed = min(speed, length / duration)
            }
            let edge = forward ? Double(piece + 1) : Double(piece)
            let stop = forward ? min(target, edge) : max(target, edge)
            let needed = abs(stop - progress) * length / speed
            if needed <= time { progress = stop; time -= needed } else {
                progress += (forward ? 1 : -1) * time * speed / length
                time = 0
            }
        }
    }

    // MARK: Narrow end and neck loop

    private func buildStatic(scale sc: Double) -> (s: Double, frame: WoundPath.Frame) {
        let g = cross
        let xs = lay.strandX + 0.9 * (1 - g)
        let ys = lay.strandY
        let yb = lay.yBottom
        let xh = -xs * (1 - g)
        let z0 = lay.sides.isEmpty ? layer : lay.sides[0] * (lay.depths[0] + 0.5) * layer
        let flip: Double = lay.insideOut ? -1 : 1
        let zc = neck.zc, th0 = 0.75
        func ring(_ th: Double) -> V3 { neck.point(th) }

        var ctrl: [V3] = [V3(xh, yb - 6, 0), V3(xh, yb - 1.2, 0), V3(mix(-xs, -0.18 * sc, g), -1.2 * sc, 0), V3(-xs, ys, 0)]
        let twoPi = 2 * Double.pi
        for th in [th0, 1.25, 1.85, 2.45, Double.pi, twoPi - 2.45, twoPi - 1.85, twoPi - 1.25, twoPi - th0] { ctrl.append(ring(th)) }
        let end = V3(xs, ys, z0)
        ctrl.append(end)
        let hang = V3(xs, ys - 3, z0)
        ctrl.append(lay.points.count > 1 ? mix(hang, v3(lay.points[1], z0), g) : hang)

        chain.removeAll(keepingCapacity: true)
        // The straight hanging part, sampled finely only at the pointed tip.
        let hangLength = max(narrow - 1.2, 4)
        var d = 0.0
        while d < hangLength - 0.3 {
            chain.append(V3(xh, yb - 1.2 - hangLength + d, 0))
            d += d < 3 ? 0.5 : 2.5
        }
        narrowTipY = yb - 1.2 - hangLength
        func tangent(_ i: Int) -> V3 {
            let before = simd_distance(ctrl[i], ctrl[i - 1]), after = simd_distance(ctrl[i + 1], ctrl[i])
            return (ctrl[i + 1] - ctrl[i - 1]) / max(before + after, 1e-6)
        }
        for i in 1..<(ctrl.count - 2) {
            let p0 = ctrl[i], p1 = ctrl[i + 1]
            let length = simd_distance(p0, p1)
            let m0 = tangent(i) * length, m1 = tangent(i + 1) * length
            let steps = max(2, Int((length / 0.45).rounded(.up)))
            for k in 0..<steps {
                let t = Double(k) / Double(steps), t2 = t * t, t3 = t2 * t
                let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t, h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
                chain.append(p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11)
            }
        }
        let center = V3(0, -1.2 * sc, 0)
        var s = 0.0
        for i in chain.indices {
            if i > 0 { s += simd_distance(chain[i], chain[i - 1]) }
            let p = chain[i]
            let ahead = i + 1 < chain.count ? chain[i + 1] : end
            let behind = i > 0 ? chain[i - 1] : p
            let t = unit(ahead - behind)
            let guide = unit(V3(p.x, 0, p.z - zc))
            let n = unit(guide - t * simd_dot(guide, t)) * flip
            let wv = TieBlank.width(s)
            let away = max(0, simd_distance(p, center) - 2.4 * sc)
            // Gathered where it passes through the knot, and kept slim just below
            // it so the narrow end stays hidden behind the blade.
            let cap = 2.1 + 0.22 * away + 3 * (1 - g)
            rows.append(Row(c: p, t: t, a: simd_cross(t, n), n: n, kappa: 0, s: s, wv: wv, wr: min(wv, cap), chord: min(wv, cap), dimple: 0))
        }
        s += simd_distance(end, chain[chain.count - 1])
        var frame = WoundPath.Frame()
        frame.p = end
        frame.t = unit(tangent(ctrl.count - 2))
        let n = V3(0, 0, flip)
        frame.n = unit(n - frame.t * simd_dot(n, frame.t))
        frame.a = simd_cross(frame.t, frame.n)
        frame.cap = 2.1 + 3 * (1 - g)
        return (s, frame)
    }

    // MARK: Wound part

    private func buildWound(from end: (s: Double, frame: WoundPath.Frame)) {
        let s0 = end.s
        woundStartS = s0
        fixedLength = s0 - narrow
        var before = 0.0
        if path.pieceCount > 0 && progress > 0 {
            for piece in 0..<path.pieceCount where Double(piece) < progress {
                let fraction = min(1, progress - Double(piece))
                let length = path.pieceLength(piece)
                let fractions: [Double]
                if piece % 2 == 0 {
                    let steps = max(1, Int((length * fraction / 0.4).rounded(.up)))
                    fractions = (0..<steps).map { fraction * Double($0) / Double(steps) }
                } else {
                    fractions = path.rollFractions(piece).filter { $0 < fraction - 1e-9 }
                }
                for f in fractions {
                    let s = s0 + before + f * length
                    if s > TieBlank.length { break }
                    let frame = path.eval(piece: piece, frac: f)
                    let wv = TieBlank.width(s), wr = min(wv, frame.cap)
                    // The dimple starts inside the knot, on the tucked chord.
                    let dimple = lay.tucked && piece == path.pieceCount - 1 ? 0.3 * tuckAmount * smoothstep(0.35, 1, f) : 0
                    rows.append(Row(c: frame.p, t: frame.t, a: frame.a, n: frame.n, kappa: frame.kappa, s: s, wv: wv, wr: wr, chord: wr, dimple: dimple))
                }
                before += length * fraction
            }
        }
        if path.pieceCount > 0 {
            anchor = path.eval(progress: progress)
            if progress <= 0 { anchor.p = end.frame.p; anchor.cap = end.frame.cap }
        } else {
            anchor = end.frame
        }
        // The free end is kept on the outer side of the layer it leaves.
        planeNormal = path.pieceCount > 0 && progress > 0 ? anchor.n : V3(0, 0, lay.insideOut ? -1 : 1)
        anchorS = min(s0 + before, TieBlank.length)
        let wv = TieBlank.width(anchorS), wr = min(wv, anchor.cap)
        rows.append(Row(c: anchor.p, t: anchor.t, a: anchor.a, n: anchor.n, kappa: anchor.kappa, s: anchorS, wv: wv, wr: wr, chord: wr, dimple: 0.3 * tuckAmount))
        shirtZ = min(-((lay.depths.max() ?? 1) + 1.5) * layer - 0.4, neck.frontZ + 0.2)
        if let band = lay.bandChord, band < path.chords.count {
            let middle = s0 + path.length(upTo: Double(2 * band) + 0.5)
            bandWidth = min(TieBlank.width(middle), (path.chords[band].cap0 + path.chords[band].cap1) / 2)
        }
    }

    // MARK: Free end

    private func resetTail() {
        for i in 0..<active {
            let d = TieBlank.length - Double(i) * seg - anchorS
            let p = anchor.p + anchor.t * min(d, 2.5) + V3(0, -1, 0) * max(0, d - 2.5) + anchor.n * 0.02
            tp[i] = p; tq[i] = p
        }
        tailSpeed = 0
    }

    private func stepTail(_ dt: Double) {
        guard active > 0, dt > 0 else { return }
        if lead > 0.25 {
            // Being led: the hang is not simulated. Keep a calm hanging shape
            // ready under the moving knot for the moment the end is released.
            let rate = 1 - exp(-dt / 0.08)
            for i in 0..<active {
                let d = TieBlank.length - Double(i) * seg - anchorS
                let rest = anchor.p + anchor.t * min(d, 2.5) + V3(0, -1, 0) * max(0, d - 2.5) + planeNormal * 0.12
                tp[i] = mix(tp[i], rest, rate)
                tq[i] = tp[i]
            }
            tailSpeed = 0
            return
        }
        let substeps = 6
        let h = dt / Double(substeps)
        let gravity = V3(0, -520, 0) * (h * h)
        let keep = max(0, 1 - 2.4 * h)
        let last = active - 1
        let first = TieBlank.length - Double(last) * seg - anchorS
        let n = planeNormal, origin = anchor.p
        let hold = 7.0
        var fastest = 0.0
        for _ in 0..<substeps {
            for i in 0..<active {
                let v = (tp[i] - tq[i]) * keep
                tq[i] = tp[i]
                tp[i] += v + gravity
            }
            for _ in 0..<5 {
                // The cloth leaves the knot along the direction of the last chord.
                var i = last
                while i >= 0 {
                    let d = first + Double(last - i) * seg
                    if d > hold { break }
                    let u = 1 - d / hold
                    let w = 0.7 * u * u
                    tp[i] = mix(tp[i], origin + anchor.t * d, w)
                    i -= 1
                }
                // Stiffness against bending.
                if last >= 2 {
                    for j in 1..<last {
                        let c = (tp[j - 1] + tp[j + 1]) * 0.5 - tp[j]
                        tp[j] += c * 0.30
                        tp[j - 1] -= c * 0.15
                        tp[j + 1] -= c * 0.15
                    }
                }
                // Links keep their length; solved from the knot outward. (A
                // follow-the-leader pass would be exact but makes the chain whip.)
                var delta = tp[last] - origin
                var length = simd_length(delta)
                if length > 1e-9 { tp[last] = origin + delta * (first / length) }
                if last >= 1 {
                    for j in stride(from: last - 1, through: 0, by: -1) {
                        delta = tp[j] - tp[j + 1]
                        length = simd_length(delta)
                        guard length > 1e-9 else { continue }
                        let fix = delta * (0.5 * (length - seg) / length)
                        tp[j] -= fix; tp[j + 1] += fix
                    }
                }
                // The free end stays on the outer side of the cloth it leaves.
                for j in 0..<active {
                    let depth = simd_dot(n, tp[j] - origin) - 0.12
                    if depth < 0 { tp[j] -= n * depth }
                    if tp[j].z < shirtZ { tp[j].z = shirtZ }
                }
            }
        }
        for i in 0..<active { fastest = max(fastest, simd_distance(tp[i], tq[i]) / h) }
        tailSpeed = fastest
    }

    /// The shape actually drawn. While a move is in progress the free end is
    /// led along its direction of travel, as a hand would hold it; when the
    /// move ends it is let go and eases into the simulated hang. The blend is
    /// made link by link in direction, so lengths are exact and it cannot
    /// tangle.
    private func poseTail() {
        guard active > 0 else { return }
        if lead < 1e-4 { for i in 0..<active { pose[i] = tp[i] }; return }
        let last = active - 1
        let first = TieBlank.length - Double(last) * seg - anchorS
        var previous = anchor.p, hung = anchor.p
        for i in stride(from: last, through: 0, by: -1) {
            let d = first + Double(last - i) * seg
            let w = lead * (1 - 0.3 * smoothstep(10, 45, d))
            let direction = turn(unit(tp[i] - hung), toward: anchor.t, by: w)
            hung = tp[i]
            pose[i] = previous + direction * (i == last ? first : seg)
            let depth = simd_dot(planeNormal, pose[i] - anchor.p) - 0.12
            if depth < 0 { pose[i] -= planeNormal * depth }
            if pose[i].z < shirtZ { pose[i].z = shirtZ }
            previous = pose[i]
        }
    }

    /// Rotates unit vector `a` toward `b`; opposite vectors turn through the
    /// outward side of the cloth so the end swings around the knot, not through it.
    private func turn(_ a: V3, toward b: V3, by w: Double) -> V3 {
        let c = simd_dot(a, b)
        if c > 0.9995 { return unit(mix(a, b, w)) }
        if c < -0.98 {
            let side = unit(planeNormal - a * simd_dot(planeNormal, a))
            return w < 0.5 ? turn(a, toward: side, by: 2 * w) : turn(side, toward: b, by: 2 * w - 1)
        }
        let angle = acos(c), sine = sin(angle)
        return unit(a * (sin((1 - w) * angle) / sine) + b * (sin(w * angle) / sine))
    }

    /// The free end while it is being threaded, as one continuous strip: down
    /// the front of the band, up again in a bight, over into the top of the
    /// band, under it, and out below. `threadLoop` is the length of the front
    /// leg; as it shrinks the tip climbs, dives under the band and the cloth
    /// follows until none is left in front.
    private func buildThread() {
        guard let leg = threadLoop, path.pieceCount > 0 else { return }
        let piece = path.pieceCount - 1
        let under = path.pieceLength(piece)
        let entry = path.eval(piece: piece, frac: 0), exit = path.eval(piece: piece, frac: 1)
        let free = freeLength
        let d = entry.t, z = V3(0, 0, 1)
        let fade = min(1, leg / 1.5)
        let front = zip(lay.sides, lay.depths).filter { $0.0 > 0 }.map(\.1).max() ?? 1
        let step = max(0.2, (front + 1.5) * layer + 0.12 - entry.p.z) * fade
        let ramp = max(0.8, 2 * step) * fade, drop = 0.8
        let turn = 0.45 * fade, over = (step + 2 * turn) / 2
        let bottom = Double.pi * turn, rise = drop * ramp + leg, top = Double.pi * over
        let marks = [ramp, ramp + leg, ramp + leg + bottom, ramp + leg + bottom + rise, ramp + leg + bottom + rise + top]
        func frame(_ u: Double) -> (p: V3, t: V3, n: V3, near: Double, below: Double) {
            if u < marks[0] {
                let f = smoothstep(0, ramp, u)
                let t = unit(d * drop + z * (step * 6 * f * (1 - f) / max(ramp, 1e-6)))
                return (entry.p + d * (drop * u) + z * (step * f), t, unit(z - t * simd_dot(z, t)), u, -1)
            }
            let base = entry.p + d * (drop * ramp + leg)
            if u < marks[1] { return (entry.p + d * (drop * ramp + u - ramp) + z * step, d, z, u, -1) }
            if u < marks[2] {
                let a = (u - marks[1]) / max(turn, 1e-6)
                return (base + z * (step + turn) + d * (turn * sin(a)) - z * (turn * cos(a)), d * cos(a) + z * sin(a), z * cos(a) - d * sin(a), min(u, marks[4] - u), -1)
            }
            if u < marks[3] { return (base - d * (u - marks[2]) + z * (step + 2 * turn), -d, -z, min(u, marks[4] - u), -1) }
            if u < marks[4] {
                let a = (u - marks[3]) / max(over, 1e-6)
                return (entry.p + z * over - d * (over * sin(a)) + z * (over * cos(a)), -d * cos(a) - z * sin(a), d * sin(a) - z * cos(a), marks[4] - u, -1)
            }
            let along = u - marks[4]
            if along <= under {
                let f = path.eval(piece: piece, frac: along / max(under, 1e-6))
                return (f.p, f.t, f.n, 0, along)
            }
            return (exit.p + exit.t * (along - under) + z * (0.12 * smoothstep(0, 1, along - under)), exit.t, z, 0, along)
        }
        wideTipY = anchor.p.y
        var u = 0.3
        while true {
            let at = min(u, free)
            let f = frame(at)
            let s = anchorS + at
            let wv = TieBlank.width(s)
            var wr = wv, chord = wv
            if f.below < 0 {
                wr = min(wv, mix(2.5, wv, smoothstep(0, 3.5, f.near)))
                chord = min(wr, mix(2.5, wv, smoothstep(-2, 9, f.near)))
            } else if f.below <= under {
                wr = min(wv, mix(2.5, 3.2, f.below / max(under, 1e-6))); chord = wr
            } else {
                wr = min(wv, mix(3.2, wv, smoothstep(0, 3.5, f.below - under)))
                chord = min(wr, mix(3.2, wv, smoothstep(-2, 9, f.below - under)))
            }
            rows.append(Row(c: f.p, t: f.t, a: simd_cross(f.t, f.n), n: f.n, kappa: 0, s: s, wv: wv, wr: wr, chord: chord, dimple: 0))
            wideTipY = min(wideTipY, f.p.y)
            if at >= free { break }
            u += 0.35
        }
        // Keep the hidden chain on the same shape so nothing jumps afterwards.
        for i in 0..<active {
            let p = frame(min(free, max(0, TieBlank.length - Double(i) * seg - anchorS))).p
            tp[i] = p; tq[i] = p; pose[i] = p
        }
        tailSpeed = 0
    }

    private func buildTail() {
        wideTipY = anchor.p.y
        guard active > 0 else { return }
        chain.removeAll(keepingCapacity: true)
        chainS.removeAll(keepingCapacity: true)
        chain.append(anchor.p); chainS.append(anchorS)
        for i in stride(from: active - 1, through: 0, by: -1) {
            let s = TieBlank.length - Double(i) * seg
            if s - anchorS < 0.15 && i > 0 { continue }
            chain.append(pose[i]); chainS.append(s)
        }
        let count = chain.count
        let widthAtKnot = min(TieBlank.width(anchorS), anchor.cap)
        var previousNormal = anchor.n
        let cup = clamp01(planeNormal.z * 2)
        func emit(_ p: V3, _ t: V3, _ s: Double) {
            var n = anchor.n - t * simd_dot(anchor.n, t)
            n = simd_length(n) > 0.2 ? unit(n) : unit(previousNormal - t * simd_dot(previousNormal, t))
            previousNormal = n
            let d = s - anchorS
            let wv = TieBlank.width(s)
            // The hem unrolls quickly; the blade then opens from a cupped
            // section to flat over the next hand-width. A free end hanging
            // behind the knot is left flat so its edges stay behind too.
            let wr = min(wv, mix(widthAtKnot, wv, smoothstep(0, 3.5, d)))
            let flare = mix(widthAtKnot, wv, smoothstep(-2, 9, d))
            let chord = min(wr, mix(wr, flare, cup))
            let dimple = 0.3 * tuckAmount * exp(-d / 6)
            let kappa = anchor.kappa * (1 - smoothstep(0, 1.5, d))
            rows.append(Row(c: p, t: t, a: simd_cross(t, n), n: n, kappa: kappa, s: s, wv: wv, wr: wr, chord: chord, dimple: dimple))
        }
        for i in 1..<count {
            let p1 = chain[i - 1], p2 = chain[i]
            let p0 = i >= 2 ? chain[i - 2] : p1 - anchor.t * simd_distance(p1, p2)
            let p3 = i + 1 < count ? chain[i + 1] : p2 * 2 - p1
            // One extra row between particles, on a Catmull–Rom curve.
            let mid = (p1 + p2) * 0.5625 - (p0 + p3) * 0.0625
            if simd_distance(p1, p2) > 0.6 {
                emit(mid, unit(p2 - p1), (chainS[i - 1] + chainS[i]) / 2)
            }
            emit(p2, unit(p3 - p1), chainS[i])
            wideTipY = min(wideTipY, p2.y)
        }
    }
}
