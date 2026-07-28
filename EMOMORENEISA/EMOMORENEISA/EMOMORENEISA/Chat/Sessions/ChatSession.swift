import Foundation
import SwiftData

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case topic, visual, roleplay, lesson, freeForum
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .topic:    return "Topic Mode"
        case .visual:   return "Visual Mode"
        case .roleplay: return "Role Play"
        case .lesson:   return "Say It Better"
        case .freeForum: return "Free Forum"
        }
    }
    var icon: String {
        switch self {
        case .topic:    return "book.fill"
        case .visual:   return "camera.fill"
        case .roleplay: return "theatermasks.fill"
        case .lesson:   return "text.bubble.fill"
        case .freeForum: return "questionmark.bubble.fill"
        }
    }

    /// Same artwork as this mode's Home menu card, so a chat's thumbnail and
    /// the filter chip for it are recognizably "the same feature" rather than
    /// a second, unrelated icon system for the same four modes.
    var homeMenuAssetName: String {
        switch self {
        case .topic:    return "btn_parrot_brain"
        case .visual:   return "btn_eye_see"
        case .roleplay: return "btn_role_play"
        case .lesson:   return "btn_explain_rules"
        case .freeForum: return "btn_free_forum"
        }
    }

    /// No TTS in this mode, ever — grammar-help answers (homework solutions,
    /// corrections, explanations) are meant to be read, not narrated; see
    /// PromptBuilder's freeForm* prompts and ChatView's generateFreeFormReply.
    var isTextOnly: Bool { self == .freeForum }
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
    var lessonId: String?

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
        case lessonId                 = "lesson_id"
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
    var lessonId: String?
    /// The most recent message TTS started playing in this session — the
    /// anchor `ChatView` scrolls back to on reopen so the screen matches
    /// what's actually been heard, instead of always jumping to the newest
    /// message. Nil until the first playback, which is also the signal for
    /// "brand-new session" (focus the first message instead).
    var lastPlayedMessageId: UUID?

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
        roleplaySceneImagePath: String? = nil,
        lessonId: String? = nil
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
        self.lessonId = lessonId
    }

    var modeEnum: SessionMode { SessionMode(rawValue: mode) ?? .topic }
}
