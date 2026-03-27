import Foundation

enum VerbType: String, Codable, CaseIterable {
    case ar, er, ir
}

enum JokerKind: String, Codable {
    case stemChanging
    case fullyIrregular
}

struct Verb: Codable, Identifiable, Equatable {
    var id: String { infinitive }
    let infinitive: String
    let type: VerbType
    let joker: Bool
    let jokerKind: JokerKind?
    let present: [String: String]

    func conjugation(for pronoun: Pronoun) -> String {
        present[pronoun.rawValue] ?? ""
    }
}
