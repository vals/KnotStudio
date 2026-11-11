import Foundation

struct TieMove: Equatable {
    enum Region: String { case L, R, C }
    let region: Region
    let inward: Bool
    var token: String { region.rawValue + (inward ? "i" : "o") }
}

struct TieSequence: Equatable {
    let moves: [TieMove]
    var notation: String { moves.map(\.token).joined() + "T" }
    var undersideAtNeck: Bool { moves.count % 2 == 1 }
    init(_ text: String) throws {
        let chars = Array(text.filter { !$0.isWhitespace })
        guard chars.last == "T" else { throw KnotError.invalid("End the sequence with one tuck, T.") }
        let body = Array(chars.dropLast())
        guard body.count % 2 == 0 else { throw KnotError.invalid("Use pairs such as Li, Ro or Co, followed by T.") }
        var parsed: [TieMove] = []
        for index in stride(from: 0, to: body.count, by: 2) {
            guard let region = TieMove.Region(rawValue: String(body[index])), ["i", "o"].contains(body[index + 1]) else {
                throw KnotError.invalid("Allowed moves: Li, Lo, Ri, Ro, Ci, Co.")
            }
            parsed.append(TieMove(region: region, inward: body[index + 1] == "i"))
        }
        guard (3...9).contains(parsed.count) else { throw KnotError.invalid("FM notation uses 3–9 moves, excluding T.") }
        guard parsed.first?.region == .L else { throw KnotError.invalid("The first move must enter L.") }
        for pair in zip(parsed, parsed.dropFirst()) {
            guard pair.0.region != pair.1.region else { throw KnotError.invalid("Consecutive moves must change region.") }
            guard pair.0.inward != pair.1.inward else { throw KnotError.invalid("Alternate inward i and outward o moves.") }
        }
        let ending = parsed.suffix(3).map(\.token).joined()
        guard ["LoRiCo", "RoLiCo"].contains(ending) else { throw KnotError.invalid("Finish Lo Ri Co T or Ro Li Co T.") }
        moves = parsed
    }
}

enum KnotError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

enum KnotKind: String, CaseIterable, Identifiable {
    case fourInHand = "Four-in-hand", pratt = "Pratt", halfWindsor = "Half-Windsor", windsor = "Windsor"
    var id: String { rawValue }
    var notation: String {
        switch self {
        case .fourInHand: return "LiRoLiCoT"
        case .pratt: return "LoCiLoRiCoT"
        case .halfWindsor: return "LiRoCiLoRiCoT"
        case .windsor: return "LiCoRiLoCiRoLiCoT"
        }
    }
    var sequence: TieSequence { try! TieSequence(notation) }
    var subtitle: String {
        switch self {
        case .fourInHand: return "A compact, asymmetric wrap"
        case .pratt: return "A central loop, with the neck fabric reversed"
        case .halfWindsor: return "One neck loop and a broader facade"
        case .windsor: return "Two neck loops and a fuller facade"
        }
    }
}
