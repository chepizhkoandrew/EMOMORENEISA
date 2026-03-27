import Foundation

struct VerbPicker {
    private let db = VerbDatabase.shared

    func pick() -> [Verb] {
        let includeJoker = Int.random(in: 0..<3) == 0

        if includeJoker {
            return pickWithJoker()
        } else {
            return pickRegular()
        }
    }

    private func pickRegular() -> [Verb] {
        guard let ar = db.ar.randomElement(),
              let er = db.er.randomElement(),
              let ir = db.ir.randomElement() else {
            return Array(db.all.prefix(3))
        }
        return [ar, er, ir].shuffled()
    }

    private func pickWithJoker() -> [Verb] {
        guard let joker = db.jokers.randomElement() else {
            return pickRegular()
        }

        let types = VerbType.allCases.filter { $0 != joker.type }

        let pool1 = regularVerbs(ofType: types[0])
        let pool2 = regularVerbs(ofType: types[1])

        guard let v1 = pool1.randomElement(),
              let v2 = pool2.randomElement() else {
            return pickRegular()
        }

        return [joker, v1, v2].shuffled()
    }

    private func regularVerbs(ofType type: VerbType) -> [Verb] {
        switch type {
        case .ar: return db.ar
        case .er: return db.er
        case .ir: return db.ir
        }
    }
}
