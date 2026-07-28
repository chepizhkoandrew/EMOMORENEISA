import Foundation

/// Mirrors `VerbDatabase`'s bundled-JSON-decoded-once convention. Bundled
/// resources here flatten to the app bundle's root at build time (confirmed
/// against the compiled .app — verbs.json, phrases.json etc. all land at the
/// top level, no subdirectory structure survives), so lessons are found by a
/// `sayItBetter_`-prefixed filename, not a resource subdirectory. Adding
/// lesson topic #2+ later needs zero code change here — only a new
/// `sayItBetter_<id>.json` file alongside `sayItBetter_goodbye.json`.
final class SayItBetterContentBank {
    static let shared = SayItBetterContentBank()

    private static let filenamePrefix = "sayItBetter_"

    private(set) var lessons: [String: Lesson] = [:]

    private init() {
        load()
    }

    private func load() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            assertionFailure("No bundled .json resources found")
            return
        }
        let decoder = JSONDecoder()
        for url in urls where url.deletingPathExtension().lastPathComponent.hasPrefix(Self.filenamePrefix) {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let lesson = try? decoder.decode(Lesson.self, from: data) else {
                assertionFailure("Failed to decode Say It Better lesson at \(url.lastPathComponent)")
                continue
            }
            lessons[lesson.id] = lesson
        }
    }

    func lesson(id: String) -> Lesson? { lessons[id] }
}
