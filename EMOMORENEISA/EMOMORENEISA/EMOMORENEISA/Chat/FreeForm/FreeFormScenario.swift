import Foundation

/// What a given "Ask in a Free Forum" turn is actually asking for — decided
/// per-message by `FreeFormScenarioClassifierService`, since a single session
/// can drift between these (a user pastes homework, then later asks a plain
/// grammar question) rather than committing to one at session start.
enum FreeFormScenario: String {
    /// User pastes/photographs a homework exercise from a textbook and wants
    /// the final correct answer(s) — quick, no elaboration.
    case homeworkHelp
    /// User describes (text/voice/photo) something they're unsure is
    /// correct Spanish. Answered as two messages: a corrected/more natural
    /// version, then a detailed explanation of why.
    case isItCorrect
    /// A general grammar/vocabulary question — plain Q&A, can run multiple
    /// turns. The safe default when the other two don't clearly apply.
    case explainMe
}
