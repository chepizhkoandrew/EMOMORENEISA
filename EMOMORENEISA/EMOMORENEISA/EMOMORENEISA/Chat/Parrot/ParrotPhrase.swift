import Foundation
import SwiftData

@Model
final class ParrotPhrase {
    @Attribute(.unique) var id: UUID
    var messageId: UUID
    var sessionId: UUID
    var selectedWords: [String]
    var spanishPhrase: String
    var englishTranslation: String
    var createdAt: Date
    var segmentPaths: [String]

    init(messageId: UUID, sessionId: UUID, selectedWords: [String], spanishPhrase: String, englishTranslation: String) {
        self.id = UUID()
        self.messageId = messageId
        self.sessionId = sessionId
        self.selectedWords = selectedWords
        self.spanishPhrase = spanishPhrase
        self.englishTranslation = englishTranslation
        self.createdAt = Date()
        self.segmentPaths = []
    }

    var hasAudio: Bool { segmentPaths.count == 7 }

    var segmentURLs: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return segmentPaths.compactMap { path in
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            } else {
                return docs.appendingPathComponent(path)
            }
        }
    }

    static func parrotDir(for id: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("esp-parrot/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
