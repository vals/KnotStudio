import Foundation

/// Fink–Mao tie notation.
///
/// The view is the mirror view: the narrow (passive) end hangs on the left, the
/// wide (active) end starts on the right. Each move names the region the wide end
/// arrives in (L, R or C) and where it points next: `i` into the shirt, `o` out
/// of the shirt. A move that ends in `i` was laid across the *front* of the knot,
/// one that ends in `o` passed *behind* it. `T` tucks the wide end down through
/// the most recent front band.
enum Region: String, CaseIterable {
    case L, R, C
    var mirrored: Region { self == .L ? .R : (self == .R ? .L : .C) }
}

struct Move: Equatable, Hashable {
    var region: Region
    var inward: Bool
    var token: String { region.rawValue + (inward ? "i" : "o") }
    /// A move ending in `i` crossed in front; one ending in `o` crossed behind.
    var crossesInFront: Bool { inward }
}

struct KnotProgram: Equatable {
    var moves: [Move] = []
    var tuck = false

    var stepCount: Int { moves.count + (tuck ? 1 : 0) }
    var tokens: [String] { moves.map(\.token) + (tuck ? ["T"] : []) }
    var notation: String { tokens.joined(separator: " ") }
    var compact: String { tokens.joined() }

    /// The knot as it stands after the first `steps` steps.
    func prefix(_ steps: Int) -> KnotProgram {
        let n = max(0, min(steps, stepCount))
        if n >= stepCount { return self }
        return KnotProgram(moves: Array(moves.prefix(n)), tuck: false)
    }

    // MARK: Rules

    /// Index of the front band a tuck would pass under, if there is one.
    /// It is the most recent chord laid across the front between L and R.
    static func tuckBand(_ moves: [Move]) -> Int? {
        guard moves.count >= 2 else { return nil }
        for k in stride(from: moves.count - 1, through: 1, by: -1)
        where moves[k].inward && moves[k].region != .C && moves[k - 1].region != .C {
            return k
        }
        return nil
    }

    static func canTuck(_ moves: [Move]) -> Bool {
        guard let last = moves.last, last.region == .C, !last.inward else { return false }
        return tuckBand(moves) != nil
    }

    static let maxMoves = 16

    /// Why `move` cannot follow `moves`, or nil when it can.
    static func objection(to move: Move, after moves: [Move]) -> String? {
        guard let last = moves.last else {
            return move.region == .C ? "The first move crosses the narrow end, so it starts with L or R." : nil
        }
        if moves.count >= maxMoves { return "That is more wraps than a tie has length for (\(maxMoves) moves)." }
        if last.region == move.region { return "\(last.token) \(move.token): the wide end is already in \(move.region.rawValue); move to another region." }
        if last.inward == move.inward {
            let want = last.inward ? "o" : "i"
            return "\(last.token) \(move.token): directions alternate, so the next move ends in “\(want)”."
        }
        return nil
    }

    static func nextMoves(after moves: [Move]) -> [Move] {
        var result: [Move] = []
        for region in Region.allCases {
            for inward in [true, false] {
                let move = Move(region: region, inward: inward)
                if objection(to: move, after: moves) == nil { result.append(move) }
            }
        }
        return result
    }

    /// True when the sequence satisfies the classical Fink–Mao finishing rule.
    var isClassical: Bool {
        guard tuck, moves.count >= 3, moves.count <= 9, moves.first?.region == .L else { return false }
        let ending = moves.suffix(3).map(\.token).joined()
        return ending == "LoRiCo" || ending == "RoLiCo"
    }

    // MARK: Parsing

    struct Parsed {
        var program: KnotProgram
        /// Set when part of the text could not be used; `program` is the valid prefix.
        var issue: String?
    }

    /// Lenient parser: case, spaces and separators are ignored, ⊗/⊙ are accepted
    /// for i/o. Returns the longest valid prefix, so half-typed text still shows
    /// a partial knot.
    static func parse(_ text: String) -> Parsed {
        var program = KnotProgram()
        let chars = Array(text).filter { !$0.isWhitespace && !",.;·-–_/|()[]".contains($0) }
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if program.tuck { return Parsed(program: program, issue: "T finishes the knot; nothing follows it.") }
            if ch == "T" || ch == "t" {
                guard canTuck(program.moves) else {
                    let why = program.moves.last.map { $0.region == .C && !$0.inward } == true
                        ? "T needs a band across the front (an Li or Ri reached from the other side) to tuck under."
                        : "T follows Co: the wide end must come up through the neck loop first."
                    return Parsed(program: program, issue: why)
                }
                program.tuck = true
                index += 1
                continue
            }
            guard let region = Region(rawValue: String(ch).uppercased()) else {
                return Parsed(program: program, issue: "“\(ch)” is not a move. Use L, R or C followed by i or o, then T.")
            }
            guard index + 1 < chars.count else {
                return Parsed(program: program, issue: "\(region.rawValue)… add i (into the shirt) or o (out of the shirt).")
            }
            let d = chars[index + 1]
            let inward: Bool
            switch d {
            case "i", "I", "⊗": inward = true
            case "o", "O", "⊙", "0": inward = false
            default:
                return Parsed(program: program, issue: "“\(region.rawValue)\(d)”: a region is followed by i or o.")
            }
            let move = Move(region: region, inward: inward)
            if let objection = objection(to: move, after: program.moves) {
                return Parsed(program: program, issue: objection)
            }
            program.moves.append(move)
            index += 2
        }
        return Parsed(program: program, issue: nil)
    }

    init(moves: [Move] = [], tuck: Bool = false) { self.moves = moves; self.tuck = tuck }
    init(_ text: String) { self = KnotProgram.parse(text).program }

    // MARK: Words

    /// A plain-language description of step `index` (0-based; the tuck is the last step).
    func describe(step index: Int) -> String {
        if index >= moves.count { return "Tuck the wide end down through the front band and pull it snug." }
        let move = moves[index]
        if index == 0 {
            let side = move.region == .L ? "left" : "right"
            return move.inward
                ? "Cross the wide end over the narrow end to the \(side)."
                : "Start inside-out and cross the wide end under the narrow end to the \(side)."
        }
        let from = moves[index - 1].region
        let front = move.inward
        switch (from, move.region) {
        case (.C, let to):
            let side = to == .L ? "left" : "right"
            return front ? "Bring it down over the front to the \(side)." : "Drop it behind the neck loop and out to the \(side)."
        case (_, .C):
            return front ? "Lift it up the front to the centre and over the neck loop." : "Pass it up behind and out through the neck loop."
        case (_, let to):
            let side = to == .L ? "left" : "right"
            return front ? "Wrap it across the front to the \(side)." : "Wrap it behind the narrow end to the \(side)."
        }
    }
}

struct NamedKnot: Identifiable, Equatable {
    let name: String
    let notation: String
    var id: String { name }
    var program: KnotProgram { KnotProgram(notation) }

    static let catalog: [NamedKnot] = [
        NamedKnot(name: "Oriental", notation: "Lo Ri Co T"),
        NamedKnot(name: "Four-in-hand", notation: "Li Ro Li Co T"),
        NamedKnot(name: "Kelvin", notation: "Lo Ri Lo Ri Co T"),
        NamedKnot(name: "Nicky", notation: "Lo Ci Ro Li Co T"),
        NamedKnot(name: "Pratt", notation: "Lo Ci Lo Ri Co T"),
        NamedKnot(name: "Victoria", notation: "Li Ro Li Ro Li Co T"),
        NamedKnot(name: "Half-Windsor", notation: "Li Ro Ci Lo Ri Co T"),
        NamedKnot(name: "St Andrew", notation: "Lo Ri Lo Ci Ro Li Co T"),
        NamedKnot(name: "Plattsburgh", notation: "Lo Ci Ro Ci Lo Ri Co T"),
        NamedKnot(name: "Cavendish", notation: "Li Ro Li Co Ri Lo Ri Co T"),
        NamedKnot(name: "Windsor", notation: "Li Co Ri Lo Ci Ro Li Co T"),
        NamedKnot(name: "Grantchester", notation: "Lo Ri Lo Ri Co Li Ro Li Co T"),
        NamedKnot(name: "Hanover", notation: "Lo Ri Co Li Ro Ci Lo Ri Co T"),
        NamedKnot(name: "Balthus", notation: "Lo Ci Ro Ci Lo Ci Ro Li Co T"),
    ]

    static func name(for program: KnotProgram) -> String? {
        catalog.first { $0.program == program }?.name
    }
}
