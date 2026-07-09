import Foundation

/// Helper for picking the right gender variant of a piece of copy.
///
/// English strings collapse to a single "neutral" variant (English second
/// person is genderless). Ukrainian ships all three variants — masculine,
/// feminine, and a gender-agnostic paraphrase (present tense / impersonal
/// constructions, NEVER plural "ви"). Any language added later must ship all
/// three variants up front.
struct GenderedString {
    let neutral: String?
    let he: String?
    let she: String?
    let they: String?

    init(neutral: String) {
        self.neutral = neutral
        self.he = nil; self.she = nil; self.they = nil
    }

    init(he: String, she: String, they: String) {
        self.neutral = nil
        self.he = he; self.she = she; self.they = they
    }

    func resolve(_ pronoun: UserPronoun) -> String {
        if let n = neutral { return n }
        switch pronoun {
        case .he:   return he ?? she ?? they ?? ""
        case .she:  return she ?? he ?? they ?? ""
        case .they: return they ?? he ?? she ?? ""
        }
    }
}
