import Foundation

final class VerbDatabase {
    static let shared = VerbDatabase()

    private(set) var all: [Verb] = []
    private(set) var ar: [Verb] = []
    private(set) var er: [Verb] = []
    private(set) var ir: [Verb] = []
    private(set) var jokers: [Verb] = []

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "verbs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("verbs.json not found in bundle")
            return
        }

        struct Root: Decodable { let verbs: [Verb] }

        guard let root = try? JSONDecoder().decode(Root.self, from: data) else {
            assertionFailure("Failed to decode verbs.json")
            return
        }

        all = root.verbs
        ar = root.verbs.filter { $0.type == .ar && !$0.joker }
        er = root.verbs.filter { $0.type == .er && !$0.joker }
        ir = root.verbs.filter { $0.type == .ir && !$0.joker }
        jokers = root.verbs.filter { $0.joker }
    }
}
