import Foundation
import simd

/// Engine checks: notation rules, geometry invariants for every classical knot
/// at every stage of tying, and the cost of a simulation step.
@main
struct Checks {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { failures += 1; print("FAIL  " + message()) }
    }

    /// Every sequence allowed by the Fink–Mao rules; there should be 85.
    static func classicalKnots() -> [KnotProgram] {
        var found: [KnotProgram] = []
        func extend(_ moves: [Move]) {
            if moves.count >= 3 {
                let program = KnotProgram(moves: moves, tuck: true)
                if program.isClassical { found.append(program) }
            }
            guard moves.count < 9 else { return }
            for next in KnotProgram.nextMoves(after: moves) { extend(moves + [next]) }
        }
        extend([Move(region: .L, inward: true)])
        extend([Move(region: .L, inward: false)])
        return found
    }

    static func segmentsCross(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> Bool {
        func side(_ p: V2, _ q: V2, _ r: V2) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }
    static func crossings(_ a: V2, _ b: V2, _ line: [V2]) -> Int {
        guard line.count > 1 else { return 0 }
        return (1..<line.count).filter { segmentsCross(a, b, line[$0 - 1], line[$0]) }.count
    }

    static func main() {
        // 1. Notation
        let knots = classicalKnots()
        expect(knots.count == 85, "expected the 85 Fink–Mao knots, enumerated \(knots.count)")
        for knot in NamedKnot.catalog {
            let parsed = KnotProgram.parse(knot.notation)
            expect(parsed.issue == nil && parsed.program.isClassical, "\(knot.name) should parse as a classical knot")
            expect(KnotProgram.parse(parsed.program.compact).program == parsed.program, "\(knot.name) should survive a round trip")
        }
        expect(KnotProgram.parse("li ro li co t").program == KnotProgram("LiRoLiCoT"), "case and spacing are ignored")
        expect(KnotProgram.parse("L⊗R⊙L⊗C⊙T").program == KnotProgram("LiRoLiCoT"), "⊗/⊙ are accepted")
        let partial = KnotProgram.parse("Li Ro L")
        expect(partial.program.moves.count == 2 && partial.issue != nil, "half-typed text keeps its valid prefix")
        expect(KnotProgram.parse("Li Lo").issue != nil, "a region cannot repeat")
        expect(KnotProgram.parse("Li Ri").issue != nil, "directions must alternate")
        expect(KnotProgram.parse("Li Ro T").issue != nil, "a tuck needs Co first")
        expect(KnotProgram.parse("Li Co T").issue != nil, "a tuck needs a front band")
        expect(KnotProgram.parse("Ci Lo").issue != nil, "the first move cannot be C")
        expect(KnotProgram("Li Ro Li Co T").prefix(2) == KnotProgram("Li Ro"), "a prefix is a partial knot")

        // 2. Geometry, for every classical knot at every step of tying.
        let sim = KnotSim()
        var states = 0, worstStretch = 0.0, worstFold = 0.0
        for knot in knots {
            for steps in 0...knot.stepCount {
                let program = knot.prefix(steps)
                sim.goal = program
                sim.settle(seconds: 0.5)
                states += 1
                let name = program.notation.isEmpty ? "untied" : program.notation
                let mesh = sim.mesh
                expect(!mesh.positions.contains { !$0.isFinite } && !mesh.normals.contains { !$0.isFinite }, "\(name): mesh has non-finite values")
                expect(sim.freeLength > 8, "\(name): the wide end ran out (\(sim.freeLength) cm left)")

                // The cloth is not stretched: distance between rows matches the material between them.
                let rows = sim.rows
                let anchor = rows.firstIndex { $0.s >= sim.anchorS - 1e-9 } ?? rows.count - 1
                for i in 1...anchor where rows[i].s - rows[i - 1].s > 0.05 {
                    let stretch = simd_distance(rows[i].c, rows[i - 1].c) / (rows[i].s - rows[i - 1].s)
                    worstStretch = max(worstStretch, abs(stretch - 1))
                    expect(abs(stretch - 1) < 0.04, "\(name): centreline stretch \(stretch) at s=\(rows[i].s)")
                }
                if anchor + 1 < rows.count {
                    for i in (anchor + 1)..<rows.count where rows[i].s - rows[i - 1].s > 0.3 {
                        let stretch = simd_distance(rows[i].c, rows[i - 1].c) / (rows[i].s - rows[i - 1].s)
                        expect(stretch > 0.85 && stretch < 1.12, "\(name): free end stretch \(stretch)")
                    }
                }

                let layout = sim.layout, path = sim.woundPath
                // Stacking: each chord lies outside every earlier chord on its side,
                // except the tuck, which sits directly under its band.
                let real = program.moves.count
                for j in 0..<real {
                    for k in 0..<j where layout.sides[k] == layout.sides[j] {
                        expect(abs(path.chords[j].z) > abs(path.chords[k].z) + 1e-6, "\(name): chord \(j) is not outside chord \(k)")
                    }
                }
                if program.tuck, let band = KnotProgram.tuckBand(program.moves.map { layout.mirrored ? Move(region: $0.region.mirrored, inward: $0.inward) : $0 }) {
                    let tuckZ = path.chords[real].z
                    expect(tuckZ > 0 && tuckZ < path.chords[band].z, "\(name): the tuck is not under its band")
                    for k in 0..<band where layout.sides[k] > 0 {
                        expect(tuckZ > path.chords[k].z, "\(name): the tuck dips under an earlier front chord")
                    }
                }
                // Folds are flat folds: the outgoing chord is the mirror image of the incoming one.
                for j in 0..<max(0, path.chords.count - 1) {
                    let roll = path.rolls[j], tin = path.chords[j].dir, tout = path.chords[j + 1].dir
                    let mirrored = roll.e * (2 * simd_dot(tin, roll.e)) - tin
                    worstFold = max(worstFold, simd_distance(mirrored, tout))
                    expect(simd_distance(mirrored, tout) < 0.02, "\(name): fold \(j) is not a reflection (\(simd_distance(mirrored, tout))) sin \(roll.sinT) lens \(path.chords[j].len) \(path.chords[j + 1].len)")
                }
                // Topology: each move crosses the strand the notation says it crosses
                // (L↔R the hanging narrow end, L↔C the left neck strand, R↔C the right).
                guard real > 0 else { continue }
                let fixed = rows.filter { $0.s < sim.woundStartS - 1e-6 }
                // The fixed part runs narrow end → left strand → behind the neck → right strand.
                let nape = fixed.indices.min { fixed[$0].c.z < fixed[$1].c.z } ?? 0
                let passive = fixed[..<nape].filter { $0.c.y > layout.yBottom - 3 && $0.c.y < 3.2 }.map { V2($0.c.x, $0.c.y) }
                let chord0 = path.chords[0]
                var cut = 0
                for i in 1..<max(passive.count, 1) where segmentsCross(chord0.start, chord0.end, passive[i - 1], passive[i]) { cut = i }
                expect(cut > 0, "\(name): the first move does not cross the narrow end")
                guard cut > 0 else { continue }
                let hanging = Array(passive[..<cut]), leftStrand = Array(passive[(cut - 1)...])
                let entry = fixed[nape...].filter { $0.c.y < 3.2 }.map { V2($0.c.x, $0.c.y) }
                let rightStrand = entry + [chord0.start, chord0.start + chord0.dir * max(0, simd_dot(passive[cut] - chord0.start, chord0.dir) - 0.05)]
                let canonical = program.moves.map { layout.mirrored ? $0.region.mirrored : $0.region }
                for j in 1..<real {
                    let c = path.chords[j]
                    let a = c.start + c.dir * 0.02, b = c.end - c.dir * 0.02
                    let counts = [crossings(a, b, hanging), crossings(a, b, leftStrand), crossings(a, b, rightStrand)]
                    let pair = Set([canonical[j - 1], canonical[j]])
                    let wanted = pair == [.L, .R] ? [1, 0, 0] : (pair == [.L, .C] ? [0, 1, 0] : [0, 0, 1])
                    expect(counts == wanted, "\(name): move \(j + 1) crosses strands \(counts), expected \(wanted)")
                    expect((c.z > 0) == program.moves[j].inward, "\(name): move \(j + 1) is on the wrong side")
                }
            }
        }
        print("geometry: \(states) knot states checked; worst centreline stretch \(String(format: "%.2f%%", worstStretch * 100)), worst fold error \(String(format: "%.4f", worstFold))")

        // Cloth weight: thicker cloth ties a bulkier knot, and still a sound one.
        for knot in NamedKnot.catalog {
            var widths: [Double] = []
            for weight in [0.75, 1.45] {
                let heavy = KnotSim()
                heavy.params.weight = weight
                heavy.goal = knot.program
                heavy.settle(seconds: 0.5)
                widths.append(heavy.layout.halfWidth)
                expect(!heavy.mesh.positions.contains { !$0.isFinite }, "\(knot.name) at weight \(weight): non-finite geometry")
                expect(heavy.freeLength > 8, "\(knot.name) at weight \(weight): the wide end ran out")
                let path = heavy.woundPath
                for j in 0..<max(0, path.chords.count - 1) {
                    let roll = path.rolls[j], tin = path.chords[j].dir
                    let mirrored = roll.e * (2 * simd_dot(tin, roll.e)) - tin
                    expect(simd_distance(mirrored, path.chords[j + 1].dir) < 0.02, "\(knot.name) at weight \(weight): fold \(j) is not a reflection")
                }
            }
            expect(widths[1] > widths[0] + 0.1, "\(knot.name): wool should tie a wider knot than fine silk")
        }

        // The tuck is threaded: partway through, the wide end stands in a bight
        // above the knot, and it ends hanging below it.
        let threader = KnotSim()
        threader.goal = KnotProgram("Li Ro Li Co")
        threader.settle()
        threader.goal = KnotProgram("Li Ro Li Co T")
        var sawBight = false, time = 0.0
        while time < 8 && (threader.isMoving || time < 0.2) {
            threader.step(1.0 / 60); time += 1.0 / 60
            let free = threader.rows.filter { $0.s > threader.anchorS }
            // A bight above the knot: cloth coming back down, face forward,
            // well above the top of the knot.
            let bight = free.contains { $0.t.y < -0.7 && $0.n.z > 0.9 && $0.c.y > threader.layout.yTop + 3 }
            if bight { sawBight = true }
            for i in 1..<max(free.count, 1) where bight && free[i].s - free[i - 1].s > 0.2 {
                let stretch = simd_distance(free[i].c, free[i - 1].c) / (free[i].s - free[i - 1].s)
                // Only stretching is an error; rows closer than their cloth just
                // straddle a turn of the bight.
                expect(stretch < 1.15, "threading: free end stretched by \(stretch)")
            }
        }
        expect(sawBight, "threading the tuck should pass through a bight above the knot")
        expect(!threader.isMoving && threader.shown.tuck, "threading should finish and come to rest")
        expect(threader.collarFold == 1, "the collar should be down once the knot is dressed")

        // 3. Live tying: each added or removed move plays out and comes to rest.
        let stepper = KnotSim()
        stepper.settle()
        let windsor = KnotProgram("Li Co Ri Lo Ci Ro Li Co T")
        stepper.fullProgram = windsor
        var slowest = 0.0, slowestName = ""
        for steps in Array(1...windsor.stepCount) + Array((0..<windsor.stepCount).reversed()) {
            stepper.goal = windsor.prefix(steps)
            var time = 0.0
            repeat { stepper.step(1.0 / 60); time += 1.0 / 60 } while stepper.isMoving && time < 12
            expect(!stepper.isMoving, "step to “\(stepper.goal.notation)” did not come to rest in 12 s")
            expect(stepper.shown == stepper.goal, "step to “\(stepper.goal.notation)” stopped short")
            expect(!stepper.mesh.positions.contains { !$0.isFinite }, "step to “\(stepper.goal.notation)” produced non-finite geometry")
            if time > slowest { slowest = time; slowestName = stepper.goal.notation }
        }
        print(String(format: "live tying: every Windsor step forward and back comes to rest; slowest %.1f s (to “%@”)", slowest, slowestName))

        // 4. Speed: tie and untie a Windsor continuously.
        let live = KnotSim()
        live.goal = KnotProgram("Li Co Ri Lo Ci Ro Li Co T")
        live.settle()
        var frames = 0, worst = 0.0
        let start = DispatchTime.now().uptimeNanoseconds
        for cycle in 0..<6 {
            live.goal = cycle % 2 == 0 ? KnotProgram() : KnotProgram("Li Co Ri Lo Ci Ro Li Co T")
            for _ in 0..<600 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                live.step(1.0 / 120)
                worst = max(worst, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
                frames += 1
            }
        }
        let mean = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(frames)
        print(String(format: "speed: %d steps, mean %.3f ms, worst %.3f ms, %d triangles (a 120 Hz frame is 8.3 ms)", frames, mean, worst, live.mesh.triangleCount))
        expect(mean < 1.0, "a step should cost well under a millisecond, measured \(mean)")

        print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
