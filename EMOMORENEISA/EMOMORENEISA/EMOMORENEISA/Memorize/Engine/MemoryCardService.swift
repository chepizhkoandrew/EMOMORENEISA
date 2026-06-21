import Foundation
import SwiftData

/// Central engine that the views and notifications consume. Owns card scheduling
/// state only — it never touches audio playback, TTS, or file I/O (those belong
/// to `LoopingParrotPlayer` / `ParrotService`). Spec §7, §8, §9.
@Observable
final class MemoryCardService {

    // MARK: Capacity-gate result types (spec §9)

    enum GateFailure: Equatable {
        case unheard(count: Int)
        case activeLearningFull(count: Int, limit: Int)
        case dailyLimitReached(count: Int, limit: Int)
        case nearTermLoadExceeded(load: Int, ceiling: Int)

        /// Inline gate-failure message for the Hub add-affordance. Spec §9.2.
        var message: String {
            switch self {
            case .unheard(let c):
                return "Hear the \(c) word\(c == 1 ? "" : "s") you already taught before adding more."
            case .activeLearningFull(_, let limit):
                return "Loro is already learning \(limit) words. Finish a few first."
            case .dailyLimitReached(_, let limit):
                return "You've taught \(limit) new words today. Come back tomorrow."
            case .nearTermLoadExceeded(_, let ceiling):
                return "This week is full (\(ceiling) plays). Let Loro catch up first."
            }
        }
    }

    enum GateResult: Equatable {
        case ok
        case blocked(GateFailure)
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Fetch helper

    private func allCards() -> [MemoryCard] {
        (try? context.fetch(FetchDescriptor<MemoryCard>())) ?? []
    }

    // MARK: - Creation gate (spec §1.3)

    /// The creation gate. Called only from the chat player when a full loop run
    /// completes (`player.isDone == true`). Idempotent per `sourceParrotId` so a
    /// manual replay never spawns a second card (E11 / Step 6 double-fire guard).
    @discardableResult
    func createCard(from phrase: ParrotPhrase, loops: Int) -> MemoryCard? {
        guard phrase.hasAudio else {
            glog("🧠 MEM", "Skip createCard — phrase \(phrase.id) has no audio")
            return nil
        }

        if let existing = allCards().first(where: { $0.sourceParrotId == phrase.id && !$0.isArchived }) {
            glog("🧠 MEM", "Card already exists for parrot \(phrase.id) — returning existing")
            return existing
        }

        let card = MemoryCard(from: phrase, loops: loops)
        card.nextDueAt = MemorizeScheduler.nextDueAt(exposureCount: 1)
        // Respect global vacation/pause mode (U12, spec §16.1): a card born while
        // pause-all is active must enter paused so it is not surfaced/scheduled.
        // `bool(forKey:)` returns false when unset, matching the setting default.
        card.isPaused = UserDefaults.standard.bool(forKey: "loro.vacationMode")
        context.insert(card)
        try? context.save()
        emitEvent(.scheduled, for: card)
        glog("🧠 MEM", "Created card \(card.id) '\(card.content)' base=\(card.repetitionsPerPhaseBase) due=\(String(describing: card.nextDueAt))")
        return card
    }

    // MARK: - Queue construction (spec §8)

    /// Live query: due, non-archived, non-paused cards, ordered Learning →
    /// Review → Mature then most-overdue first, capped at `sessionCap`. Filtered
    /// and sorted in Swift (not all predicates compose in `#Predicate`).
    func buildQueue(sessionCap: Int = 20, now: Date = Date()) -> [MemoryCard] {
        let due = allCards().filter { card in
            !card.isArchived
                && !card.isPaused
                && card.nextDueAt != nil
                && card.nextDueAt! <= now
        }

        let sorted = due.sorted { a, b in
            if a.exposureCount != b.exposureCount {
                return a.exposureCount < b.exposureCount
            }
            // Clamp negative/jumped clocks to "due now" (E8) via max(0, …).
            let aOverdue = max(0, now.timeIntervalSince(a.nextDueAt!))
            let bOverdue = max(0, now.timeIntervalSince(b.nextDueAt!))
            if abs(aOverdue - bOverdue) > 60 {
                return aOverdue > bOverdue
            }
            // Stable tiebreak within the same urgency (deterministic for tests;
            // prevents sequence memorization across sessions).
            return a.id.uuidString < b.id.uuidString
        }

        return Array(sorted.prefix(sessionCap))
    }

    /// Count of cards currently due (for badges and notifications).
    func dueCount(now: Date = Date()) -> Int {
        allCards().filter {
            !$0.isArchived && !$0.isPaused && $0.nextDueAt != nil && $0.nextDueAt! <= now
        }.count
    }

    // MARK: - Atomic play update (spec §7)

    /// A scheduled visit completed (all `repetitionsThisPhase` loops finished).
    /// Advances the card by one exposure and reschedules — or archives at 13.
    func onVisitDidComplete(_ card: MemoryCard, now: Date = Date()) {
        card.exposureCount += 1
        card.lastPlayedAt = now

        if card.exposureCount >= 13 {
            card.nextDueAt = nil
            card.isArchived = true
            try? context.save()
            emitEvent(.archived, for: card)
            glog("🧠 MEM", "🎉 Card \(card.id) '\(card.content)' etched in microchip (archived)")
        } else {
            card.nextDueAt = MemorizeScheduler.nextDueAt(exposureCount: card.exposureCount, from: now)
            try? context.save()
            emitEvent(.played, for: card)
            glog("🧠 MEM", "Card \(card.id) → exposure \(card.exposureCount), next due \(String(describing: card.nextDueAt))")
        }
    }

    // MARK: - Derived metrics (spec §9.1, computed not stored)

    var unheardCount: Int {
        allCards().filter { !$0.isArchived && $0.exposureCount == 0 }.count
    }

    var activeLearningCount: Int {
        allCards().filter { !$0.isArchived && (1...5).contains($0.exposureCount) }.count
    }

    var knownCount: Int {
        allCards().filter { $0.isArchived }.count
    }

    var totalCount: Int { allCards().count }

    func newTodayCount(now: Date = Date()) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        return allCards().filter { $0.createdAt >= start }.count
    }

    /// Number of scheduled visits falling due within the next `horizonDays`,
    /// simulated by walking each card forward through the interval ladder.
    func nearTermLoad(now: Date = Date(), horizonDays: Int = 7) -> Int {
        let limit = now.addingTimeInterval(Double(horizonDays) * 86400)
        var total = 0
        for card in allCards() where !card.isArchived && !card.isPaused {
            var exposure = card.exposureCount
            var due = card.nextDueAt
            while let d = due, d <= limit, exposure < 13 {
                total += 1
                exposure += 1
                due = MemorizeScheduler.nextDueAt(exposureCount: exposure, from: d)
            }
        }
        return total
    }

    // MARK: - Capacity gates (spec §9)

    /// Gates checked in order; first failure blocks creation. In the chat-only
    /// Phase 1 slice these do NOT block `createCard(from:)` (completion is the
    /// signal, spec §1.3); they gate the Hub's add-affordance. Gate 1
    /// (`unheardCount == 0`) passes by construction today because no creation
    /// path produces `exposureCount == 0` cards.
    func checkGates(
        maxActiveLearning: Int = 20,
        dailyNewLimit: Int = 5,
        maxNearTermLoad: Int = 40,
        now: Date = Date()
    ) -> GateResult {
        let unheard = unheardCount
        if unheard > 0 { return .blocked(.unheard(count: unheard)) }

        let active = activeLearningCount
        if active >= maxActiveLearning {
            return .blocked(.activeLearningFull(count: active, limit: maxActiveLearning))
        }

        let today = newTodayCount(now: now)
        if today >= dailyNewLimit {
            return .blocked(.dailyLimitReached(count: today, limit: dailyNewLimit))
        }

        let load = nearTermLoad(now: now)
        if load >= maxNearTermLoad {
            return .blocked(.nearTermLoadExceeded(load: load, ceiling: maxNearTermLoad))
        }

        return .ok
    }

    // MARK: - Card management actions (spec §13, subset)

    /// U2 — snooze: push the next visit out, persisted.
    func snooze(_ card: MemoryCard, by interval: TimeInterval, now: Date = Date()) {
        card.snoozedUntil = now.addingTimeInterval(interval)
        card.nextDueAt = card.snoozedUntil
        try? context.save()
        emitEvent(.snoozed, for: card)
    }

    /// U3 — "already knows": jump straight to archived/microchip.
    func markAlreadyKnown(_ card: MemoryCard) {
        card.exposureCount = 13
        card.isArchived = true
        card.nextDueAt = nil
        card.lastPlayedAt = Date()
        try? context.save()
        emitEvent(.archived, for: card)
    }

    /// U6 — re-teach an archived card: reset to the Review tier (spec D4).
    func reteach(_ card: MemoryCard, now: Date = Date()) {
        card.exposureCount = 6
        card.isArchived = false
        card.nextDueAt = MemorizeScheduler.nextDueAt(exposureCount: 6, from: now)
        try? context.save()
        emitEvent(.scheduled, for: card)
    }

    /// U12 — vacation/pause: freeze scheduling without losing progress.
    func setPaused(_ card: MemoryCard, _ paused: Bool) {
        card.isPaused = paused
        try? context.save()
        emitEvent(paused ? .snoozed : .scheduled, for: card)
    }

    /// U4 — delete: frees Gate 2 capacity.
    func delete(_ card: MemoryCard) {
        emitEvent(.deleted, for: card)
        context.delete(card)
        try? context.save()
    }

    // MARK: - Supabase event mirror hook (spec §4.2)

    enum MemoryEventKind: String {
        case scheduled, played, skipped, snoozed, archived, deleted
    }

    /// Fire-and-forget stats mirror. Audio bytes never leave the device.
    /// The remote upsert is implemented in `RemoteMemoryCard` /
    /// `SupabaseSyncService.upsertMemoryCard`; this hook stays best-effort and
    /// never blocks the passive session.
    private func emitEvent(_ kind: MemoryEventKind, for card: MemoryCard) {
        glog("🧠 MEM", "event=\(kind.rawValue) card=\(card.id) exposure=\(card.exposureCount)")
        let snapshot = RemoteMemoryCard(card: card, event: kind.rawValue)
        Task.detached {
            await SupabaseSyncService.shared.upsertMemoryCard(snapshot)
        }
    }
}
