import Foundation

/// Mirrors `SayItBetterContentBank`'s bundled-JSON-decoded-once convention,
/// except this curriculum is authored as ONE file (`learnByBook_topics.json`)
/// rather than one file per topic — the whole fixed textbook curriculum is
/// planned and versioned together, unlike Say It Better's per-lesson files
/// that get added one at a time.
final class LearnByBookContentBank {
    static let shared = LearnByBookContentBank()

    private(set) var levels: [LearnByBookLevel] = []
    private(set) var topics: [LearnByBookTopic] = []

    private init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "learnByBook_topics", withExtension: "json") else {
            assertionFailure("learnByBook_topics.json not found in bundle")
            glog("[LearnByBook]", "FATAL: learnByBook_topics.json not found in bundle")
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            assertionFailure("Failed to read learnByBook_topics.json")
            glog("[LearnByBook]", "FATAL: failed to read learnByBook_topics.json at \(url)")
            return
        }
        do {
            let curriculum = try JSONDecoder().decode(LearnByBookCurriculum.self, from: data)
            levels = curriculum.levels
            topics = curriculum.topics.sorted { $0.order < $1.order }
        } catch {
            // A Release build must not go on with an empty curriculum
            // silently — `assertionFailure` alone is a no-op there, so this
            // is the only trace that the whole mode went blank.
            assertionFailure("Failed to decode learnByBook_topics.json: \(error)")
            glog("[LearnByBook]", "FATAL: failed to decode learnByBook_topics.json: \(error)")
        }
    }

    func topics(forLevel levelId: String) -> [LearnByBookTopic] {
        topics.filter { $0.levelId == levelId }
    }
}
