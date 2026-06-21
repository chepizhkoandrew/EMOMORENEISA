import Foundation
import SwiftData

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case topic, visual
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .topic:  return "Topic Mode"
        case .visual: return "Visual Mode"
        }
    }
    var icon: String {
        switch self {
        case .topic:  return "book.fill"
        case .visual: return "camera.fill"
        }
    }
}

struct RemoteChatSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var mode: String
    var title: String?
    var topic: String?
    var sessionGoal: String?
    var messageCount: Int
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId             = "user_id"
        case mode, title, topic
        case sessionGoal        = "session_goal"
        case messageCount       = "message_count"
        case lastMessagePreview = "last_message_preview"
        case lastMessageAt      = "last_message_at"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
    }
}

@Model
final class LocalChatSession {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var mode: String
    var title: String?
    var topic: String?
    var sessionGoal: String?
    var messageCount: Int
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isSynced: Bool

    @Relationship(deleteRule: .cascade) var messages: [LocalChatMessage] = []

    init(id: UUID = UUID(), userId: UUID, mode: SessionMode, title: String? = nil, topic: String? = nil) {
        self.id = id
        self.userId = userId
        self.mode = mode.rawValue
        self.title = title
        self.topic = topic
        self.sessionGoal = topic
        self.messageCount = 0
        self.lastMessagePreview = topic
        self.lastMessageAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isSynced = false
    }

    var modeEnum: SessionMode { SessionMode(rawValue: mode) ?? .topic }
}
