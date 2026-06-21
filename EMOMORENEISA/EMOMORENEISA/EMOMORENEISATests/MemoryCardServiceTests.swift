import XCTest
import SwiftData
@testable import EMOMORENEISA

/// Service-level tests over an in-memory SwiftData container (spec §1.3, §7, §8, §9).
/// `MemoryCardService` is MainActor-isolated (app default), so the suite is too.
@MainActor
final class MemoryCardServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: MemoryCardService!

    override func setUp() {
        super.setUp()
        let schema = Schema([MemoryCard.self, ParrotPhrase.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        service = MemoryCardService(context: context)
    }

    override func tearDown() {
        service = nil
        context = nil
        container = nil
        super.tearDown()
    }

    private func makePhraseWithAudio() -> ParrotPhrase {
        let phrase = ParrotPhrase(
            messageId: UUID(),
            sessionId: UUID(),
            selectedWords: ["hola"],
            spanishPhrase: "Hola, ¿qué tal?",
            englishTranslation: "Hi, how are you?"
        )
        phrase.segmentPaths = (1...7).map { "/tmp/\($0).wav" }
        context.insert(phrase)
        return phrase
    }

    // MARK: createCard (spec §1.3)

    func test_createCard_fromCompletedLoopRun_setsExposureOneAndTwentyMinuteDue() {
        let phrase = makePhraseWithAudio()
        let before = Date()
        let card = service.createCard(from: phrase, loops: 8)

        let unwrapped = try! XCTUnwrap(card)
        XCTAssertEqual(unwrapped.exposureCount, 1)
        XCTAssertEqual(unwrapped.repetitionsPerPhaseBase, 8)
        XCTAssertEqual(unwrapped.audioSegmentPaths, phrase.segmentPaths)
        XCTAssertEqual(unwrapped.sourceParrotId, phrase.id)
        XCTAssertFalse(unwrapped.isArchived)

        let due = try! XCTUnwrap(unwrapped.nextDueAt)
        let expected = before.addingTimeInterval(20 * 60)
        XCTAssertEqual(due.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 5)
    }

    func test_createCard_calledTwiceForSamePhrase_createsExactlyOneCard_idempotent() {
        let phrase = makePhraseWithAudio()
        let first = service.createCard(from: phrase, loops: 4)
        let second = service.createCard(from: phrase, loops: 4)

        XCTAssertEqual(first?.id, second?.id)
        let all = try! context.fetch(FetchDescriptor<MemoryCard>())
        XCTAssertEqual(all.count, 1)
    }

    func test_createCard_whenVacationModeActive_newCardIsPaused() {
        let key = "loro.vacationMode"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(true, forKey: key)
        let phrase = makePhraseWithAudio()
        let card = try! XCTUnwrap(service.createCard(from: phrase, loops: 5))
        XCTAssertTrue(card.isPaused)
    }

    func test_createCard_whenVacationModeInactive_newCardIsNotPaused() {
        let key = "loro.vacationMode"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(false, forKey: key)
        let phrase = makePhraseWithAudio()
        let card = try! XCTUnwrap(service.createCard(from: phrase, loops: 5))
        XCTAssertFalse(card.isPaused)
    }

    func test_createCard_phraseWithoutSevenSegments_returnsNil() {
        let phrase = ParrotPhrase(
            messageId: UUID(), sessionId: UUID(), selectedWords: [],
            spanishPhrase: "x", englishTranslation: "y"
        )
        phrase.segmentPaths = ["/tmp/1.wav"]
        context.insert(phrase)
        XCTAssertNil(service.createCard(from: phrase, loops: 4))
    }

    // MARK: onVisitDidComplete (spec §7)

    func test_onVisitDidComplete_atTwelve_archivesAtThirteenWithNilDue() {
        let phrase = makePhraseWithAudio()
        let card = service.createCard(from: phrase, loops: 5)!
        card.exposureCount = 12

        service.onVisitDidComplete(card)

        XCTAssertEqual(card.exposureCount, 13)
        XCTAssertTrue(card.isArchived)
        XCTAssertNil(card.nextDueAt)
    }

    func test_onVisitDidComplete_atOne_advancesToTwoWithNewDueDate() {
        let phrase = makePhraseWithAudio()
        let card = service.createCard(from: phrase, loops: 5)!

        service.onVisitDidComplete(card)

        XCTAssertEqual(card.exposureCount, 2)
        XCTAssertFalse(card.isArchived)
        XCTAssertNotNil(card.nextDueAt)
    }

    // MARK: buildQueue (spec §8)

    func test_buildQueue_returnsOnlyDueNonArchivedNonPaused_orderedByExposure() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let pastA = now.addingTimeInterval(-3600)
        let pastB = now.addingTimeInterval(-60)
        let future = now.addingTimeInterval(3600)

        let dueLowExposure = MemoryCard(content: "a", translation: "a", exposureCount: 1, nextDueAt: pastB)
        let dueHighExposure = MemoryCard(content: "b", translation: "b", exposureCount: 4, nextDueAt: pastA)
        let notYetDue = MemoryCard(content: "c", translation: "c", exposureCount: 1, nextDueAt: future)
        let archived = MemoryCard(content: "d", translation: "d", exposureCount: 13, nextDueAt: nil, isArchived: true)
        let paused = MemoryCard(content: "e", translation: "e", exposureCount: 1, nextDueAt: pastA, isPaused: true)

        [dueLowExposure, dueHighExposure, notYetDue, archived, paused].forEach { context.insert($0) }
        try! context.save()

        let queue = service.buildQueue(now: now)
        XCTAssertEqual(queue.map(\.content), ["a", "b"])
    }

    func test_buildQueue_honorsSessionCap() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        for i in 0..<10 {
            let c = MemoryCard(content: "w\(i)", translation: "w\(i)",
                               exposureCount: 1, nextDueAt: now.addingTimeInterval(-60))
            context.insert(c)
        }
        try! context.save()
        XCTAssertEqual(service.buildQueue(sessionCap: 3, now: now).count, 3)
    }

    // MARK: Derived metrics (spec §9.1)

    func test_activeLearningCount_countsOnlyExposureOneThroughFive() {
        [1, 3, 5, 6, 11].forEach {
            context.insert(MemoryCard(content: "x", translation: "x", exposureCount: $0,
                                      nextDueAt: Date()))
        }
        context.insert(MemoryCard(content: "z", translation: "z", exposureCount: 13,
                                  nextDueAt: nil, isArchived: true))
        try! context.save()
        XCTAssertEqual(service.activeLearningCount, 3)
    }

    func test_newTodayCount_respectsDeviceLocalMidnight() {
        let now = Date()
        let today = MemoryCard(content: "t", translation: "t", exposureCount: 1,
                               nextDueAt: now, createdAt: now)
        let yesterday = MemoryCard(content: "y", translation: "y", exposureCount: 1,
                                   nextDueAt: now,
                                   createdAt: Calendar.current.startOfDay(for: now).addingTimeInterval(-3600))
        context.insert(today)
        context.insert(yesterday)
        try! context.save()
        XCTAssertEqual(service.newTodayCount(now: now), 1)
    }
}
