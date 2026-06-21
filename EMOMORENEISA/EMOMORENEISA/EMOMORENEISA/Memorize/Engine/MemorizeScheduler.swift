import Foundation

/// The Loro Memorize scheduling engine: the 13-step interval ladder and the
/// per-phase repetition decay. Pure, stateless, `nonisolated` static functions
/// so they are trivially unit-testable with no SwiftData and no MainActor hop.
/// Spec §6.
enum MemorizeScheduler {

    /// 13 minimum intervals before the next scheduled visit, indexed by
    /// `exposureCount - 1` (Learning 1 … Mature 3). Spec §6.2.
    nonisolated static let phaseIntervals: [TimeInterval] = [
        20 * 60,        // Learning 1  — 20 min
        2 * 3600,       // Learning 2  — 2 hours
        8 * 3600,       // Learning 3  — 8 hours
        86400,          // Learning 4  — 1 day
        2 * 86400,      // Learning 5  — 2 days
        4 * 86400,      // Review 1    — 4 days
        7 * 86400,      // Review 2    — 7 days
        14 * 86400,     // Review 3    — 14 days
        30 * 86400,     // Review 4    — 30 days
        60 * 86400,     // Review 5    — 60 days
        90 * 86400,     // Mature 1    — 90 days
        180 * 86400,    // Mature 2    — 180 days
        365 * 86400     // Mature 3    — 365 days (then archived)
    ]

    /// Next due date for a card that has just reached `exposureCount`.
    /// Returns `nil` once the card has been heard 13 times (archived).
    /// `now` is injectable for deterministic tests and E8 clock-jump tolerance.
    nonisolated static func nextDueAt(exposureCount: Int, from now: Date = Date()) -> Date? {
        guard exposureCount > 0 else { return now }       // unheard → due immediately
        guard exposureCount < 13 else { return nil }      // archived after the 13th play
        return now.addingTimeInterval(phaseIntervals[exposureCount - 1])
    }

    /// How many full 7-part loops this scheduled visit requires.
    /// Decays from `base` by ×0.7 each phase, clamped to a minimum of 1.
    ///
    /// Implemented as *iterative* rounding (round previous × 0.7) per the worked
    /// examples in spec §6.2 — e.g. base 10 → 10, 7, 5, 4, 3, 2, 1. A closed-form
    /// `round(base * 0.7^(n-1))` diverges at step 4 (3 vs 4), so the iterative
    /// form is authoritative.
    nonisolated static func repetitionsThisPhase(exposureCount: Int, base: Int) -> Int {
        let start = max(1, base)
        guard exposureCount > 1 else { return start }
        var value = start
        for _ in 1..<exposureCount {
            value = max(1, Int((Double(value) * 0.7).rounded()))
        }
        return value
    }

    /// Internal phase label (e.g. "Learning 3", "Review 2", "Mature 1").
    /// For debug/analytics only — never shown raw to the user. Spec §6.1.
    nonisolated static func phaseLabel(exposureCount: Int) -> String {
        switch exposureCount {
        case ..<1:    return "New"
        case 1...5:   return "Learning \(exposureCount)"
        case 6...10:  return "Review \(exposureCount - 5)"
        case 11...13: return "Mature \(exposureCount - 10)"
        default:      return "Mastered"
        }
    }
}
