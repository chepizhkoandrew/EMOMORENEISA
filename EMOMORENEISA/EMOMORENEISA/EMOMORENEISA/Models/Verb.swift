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
    let preterite: [String: String]
    let imperfect: [String: String]
    let future: [String: String]
    let translation: String?

    func conjugation(for pronoun: Pronoun, tense: Tense) -> String {
        let table: [String: String]
        switch tense {
        case .present: table = present
        case .preterite: table = preterite
        case .imperfect: table = imperfect
        case .future: table = future
        }
        return table[pronoun.rawValue] ?? ""
    }
}
