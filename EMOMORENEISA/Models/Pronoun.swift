import Foundation

enum Pronoun: String, CaseIterable, Codable, Identifiable {
    case yo
    case tu
    case el
    case nosotros
    case vosotros
    case ellos

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .yo:       return "yo"
        case .tu:       return "tú"
        case .el:       return "él / ella"
        case .nosotros: return "nosotros"
        case .vosotros: return "vosotros"
        case .ellos:    return "ellos / ellas"
        }
    }
}
