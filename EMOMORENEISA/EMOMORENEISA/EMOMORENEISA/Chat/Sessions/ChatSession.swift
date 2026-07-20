import Foundation
import SwiftData

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case topic, visual, roleplay
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .topic:    return "Topic Mode"
        case .visual:   return "Visual Mode"
        case .roleplay: return "Role Play"
        }
    }
    var icon: String {
        switch self {
        case .topic:    return "book.fill"
        case .visual:   return "camera.fill"
        case .roleplay: return "theatermasks.fill"
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
    var roleplayObjectLabel: String?
    var roleplayEnvironmentLabel: String?
    var roleplayObjectVoice: String?
    var roleplaySceneImagePath: String?

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
        case roleplayObjectLabel      = "roleplay_object_label"
        case roleplayEnvironmentLabel = "roleplay_environment_label"
        case roleplayObjectVoice      = "roleplay_object_voice"
        case roleplaySceneImagePath   = "roleplay_scene_image_path"
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
    var roleplayObjectLabel: String?
    var roleplayEnvironmentLabel: String?
    var roleplayObjectVoice: String?
    var roleplaySceneImagePath: String?

    @Relationship(deleteRule: .cascade) var messages: [LocalChatMessage] = []

    init(
        id: UUID = UUID(),
        userId: UUID,
        mode: SessionMode,
        title: String? = nil,
        topic: String? = nil,
        roleplayObjectLabel: String? = nil,
        roleplayEnvironmentLabel: String? = nil,
        roleplayObjectVoice: String? = nil,
        roleplaySceneImagePath: String? = nil
    ) {
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
        self.roleplayObjectLabel = roleplayObjectLabel
        self.roleplayEnvironmentLabel = roleplayEnvironmentLabel
        self.roleplayObjectVoice = roleplayObjectVoice
        self.roleplaySceneImagePath = roleplaySceneImagePath
    }

    var modeEnum: SessionMode { SessionMode(rawValue: mode) ?? .topic }
}
