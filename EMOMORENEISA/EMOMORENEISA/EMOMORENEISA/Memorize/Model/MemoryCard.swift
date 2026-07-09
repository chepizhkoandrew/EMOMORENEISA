import Foundation
import SwiftData

@Model
final class MemoryCard {
    @Attribute(.unique) var id: UUID
    var content: String
    var translation: String
    var audioSegmentPaths: [String]
    /// Relative path to the memorization illustration (mirrors ParrotPhrase). nil
    /// when the source phrase had no illustration.
    var illustrationPath: String?
    var sourceWordId: UUID?
    var sourceParrotId: UUID?

    var exposureCount: Int
    var lastPlayedAt: Date?
    var nextDueAt: Date?
    var isArchived: Bool

    var repetitionsPerPhaseBase: Int
    var createdAt: Date

    var snoozedUntil: Date?
    var isPaused: Bool = false

    init(
        id: UUID = UUID(),
        content: String,
        translation: String,
        audioSegmentPaths: [String] = [],
        illustrationPath: String? = nil,
        sourceWordId: UUID? = nil,
        sourceParrotId: UUID? = nil,
        exposureCount: Int = 1,
        lastPlayedAt: Date? = nil,
        nextDueAt: Date? = nil,
        isArchived: Bool = false,
        repetitionsPerPhaseBase: Int = 5,
        createdAt: Date = Date(),
        snoozedUntil: Date? = nil,
        isPaused: Bool = false
    ) {
        self.id = id
        self.content = content
        self.translation = translation
        self.audioSegmentPaths = audioSegmentPaths
        self.illustrationPath = illustrationPath
        self.sourceWordId = sourceWordId
        self.sourceParrotId = sourceParrotId
        self.exposureCount = exposureCount
        self.lastPlayedAt = lastPlayedAt
        self.nextDueAt = nextDueAt
        self.isArchived = isArchived
        self.repetitionsPerPhaseBase = repetitionsPerPhaseBase
        self.createdAt = createdAt
        self.snoozedUntil = snoozedUntil
        self.isPaused = isPaused
    }

    /// Born from a completed ParrotService loop run. Reuses the 7 on-disk WAV paths
    /// already produced by ParrotService — no audio is duplicated or re-generated.
    convenience init(from phrase: ParrotPhrase, loops: Int) {
        self.init(
            content: phrase.spanishPhrase,
            translation: phrase.englishTranslation,
            audioSegmentPaths: phrase.segmentPaths,
            illustrationPath: phrase.illustrationPath,
            sourceParrotId: phrase.id,
            exposureCount: 1,
            repetitionsPerPhaseBase: max(1, loops)
        )
    }

    // MARK: - Computed helpers (never stored)

    /// Mirrors `ParrotPhrase.hasAudio`. The 7 paths already point at
    /// `ParrotPhrase.parrotDir(for:)/N.wav`; do not re-derive the directory.
    var hasAudio: Bool { audioSegmentPaths.count == 7 }

    /// Mirrors `ParrotPhrase.segmentURLs`.
    var segmentURLs: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return audioSegmentPaths.compactMap { path in
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            } else {
                return docs.appendingPathComponent(path)
            }
        }
    }

    /// On-disk URL of the memorization illustration, or nil when none was saved.
    var illustrationURL: URL? {
        guard let path = illustrationPath else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(path)
    }

    /// The single user-visible material/horizon stage for this card.
    var stage: MemoryStage { MemoryStage.stage(forExposureCount: exposureCount) }

    /// Refreshers remaining before the card is etched in a microchip (archived).
    var refreshersRemaining: Int { max(0, 13 - exposureCount) }
}
