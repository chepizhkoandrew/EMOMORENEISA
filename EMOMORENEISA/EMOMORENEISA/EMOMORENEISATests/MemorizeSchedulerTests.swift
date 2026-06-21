import XCTest
@testable import EMOMORENEISA

/// Pure-engine tests for the interval ladder and repetition decay (spec §6).
/// No SwiftData, no UI — the scheduler is stateless static functions.
final class MemorizeSchedulerTests: XCTestCase {

    // MARK: repetitionsThisPhase — decay ×0.7, floor 1 (spec §5.2 worked examples)

    func test_repetitionsThisPhase_base10_decaysAcrossSevenPhases() {
        let base = 10
        let got = (1...7).map {
            MemorizeScheduler.repetitionsThisPhase(exposureCount: $0, base: base)
        }
        XCTAssertEqual(got, [10, 7, 5, 4, 3, 2, 1])
    }

    func test_repetitionsThisPhase_base4_decaysAndFloorsAtOne() {
        let base = 4
        let got = (1...6).map {
            MemorizeScheduler.repetitionsThisPhase(exposureCount: $0, base: base)
        }
        XCTAssertEqual(got, [4, 3, 2, 1, 1, 1])
    }

    func test_repetitionsThisPhase_neverBelowOne_evenWithLargeExposure() {
        for exposure in 1...13 {
            let n = MemorizeScheduler.repetitionsThisPhase(exposureCount: exposure, base: 10)
            XCTAssertGreaterThanOrEqual(n, 1, "phase \(exposure) dropped below 1")
        }
    }

    func test_repetitionsThisPhase_firstPhaseEqualsBase() {
        XCTAssertEqual(MemorizeScheduler.repetitionsThisPhase(exposureCount: 1, base: 5), 5)
    }

    // MARK: nextDueAt — interval ladder with a pinned clock (spec §6.2)

    func test_nextDueAt_learning1_isTwentyMinutesOut() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let due = MemorizeScheduler.nextDueAt(exposureCount: 1, from: now)
        XCTAssertEqual(due, now.addingTimeInterval(20 * 60))
    }

    func test_nextDueAt_learning5_isTwoDaysOut() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let due = MemorizeScheduler.nextDueAt(exposureCount: 5, from: now)
        XCTAssertEqual(due, now.addingTimeInterval(2 * 86400))
    }

    func test_nextDueAt_thirteenthExposure_isNilArchived() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(MemorizeScheduler.nextDueAt(exposureCount: 13, from: now))
    }

    func test_nextDueAt_zeroExposure_isDueImmediately() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MemorizeScheduler.nextDueAt(exposureCount: 0, from: now), now)
    }

    // MARK: MemoryStage — 13→5 compression boundaries (spec §3.1)

    func test_memoryStage_boundaries_mapToFiveMaterials() {
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 0), .agua)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 1), .agua)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 2), .wood)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 5), .wood)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 6), .stone)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 10), .stone)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 11), .gold)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 12), .gold)
        XCTAssertEqual(MemoryStage.stage(forExposureCount: 13), .microchip)
    }
}
