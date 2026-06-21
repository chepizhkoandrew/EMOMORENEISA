import Foundation
import SwiftData

@Model
final class StreetAnnotation {
    @Attribute(.unique) var id: UUID
    var assistantMessageId: UUID
    var userMessageId: UUID
    var sessionId: UUID
    var annotationsJSON: String
    var createdAt: Date

    init(assistantMessageId: UUID, userMessageId: UUID, sessionId: UUID, annotationsJSON: String) {
        self.id = UUID()
        self.assistantMessageId = assistantMessageId
        self.userMessageId = userMessageId
        self.sessionId = sessionId
        self.annotationsJSON = annotationsJSON
        self.createdAt = Date()
    }

    var annotations: [AnnotationItem] {
        guard let data = annotationsJSON.data(using: .utf8),
              let items = try? JSONDecoder().decode([AnnotationItem].self, from: data) else {
            return []
        }
        return items
    }
}

struct AnnotationItem: Codable, Identifiable {
    let label: String
    let translation: String
    let x: Double
    let y: Double

    var id: String { label }
}
