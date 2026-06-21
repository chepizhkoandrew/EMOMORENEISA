import Foundation
import SwiftData

enum MessageSender: String, Codable { case user, assistant }
enum MessageType: String, Codable { case text, audio, image, mixed }

struct RemoteChatMessage: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    var threadParentId: UUID?
    var sender: String
    var type: String
    var textContent: String?
    var rawTranscript: String?
    var audioStoragePath: String?
    var imageStoragePaths: [String]
    var isEnhanced: Bool
    var threadReplyCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId          = "session_id"
        case threadParentId     = "thread_parent_id"
        case sender, type
        case textContent        = "text_content"
        case rawTranscript      = "raw_transcript"
        case audioStoragePath   = "audio_storage_path"
        case imageStoragePaths  = "image_storage_paths"
        case isEnhanced         = "is_enhanced"
        case threadReplyCount   = "thread_reply_count"
        case createdAt          = "created_at"
    }
}

@Model
final class LocalChatMessage {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var threadParentId: UUID?
    var sender: String
    var type: String
    var textContent: String?
    var rawTranscript: String?
    var audioLocalPath: String?
    var imageLocalPaths: [String]
    var isEnhanced: Bool
    var threadReplyCount: Int
    var createdAt: Date
    var isSynced: Bool

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        threadParentId: UUID? = nil,
        sender: MessageSender,
        type: MessageType,
        textContent: String? = nil,
        rawTranscript: String? = nil,
        audioLocalPath: String? = nil,
        imageLocalPaths: [String] = []
    ) {
        self.id = id
        self.sessionId = sessionId
        self.threadParentId = threadParentId
        self.sender = sender.rawValue
        self.type = type.rawValue
        self.textContent = textContent
        self.rawTranscript = rawTranscript
        self.audioLocalPath = audioLocalPath
        self.imageLocalPaths = imageLocalPaths
        self.isEnhanced = false
        self.threadReplyCount = 0
        self.createdAt = Date()
        self.isSynced = false
    }

    var senderEnum: MessageSender { MessageSender(rawValue: sender) ?? .user }
    var typeEnum: MessageType { MessageType(rawValue: type) ?? .text }
    var isUser: Bool { senderEnum == .user }
    var isAssistant: Bool { senderEnum == .assistant }
    var isRootMessage: Bool { threadParentId == nil }

    var resolvedImagePaths: [String] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        return imageLocalPaths.map { path in
            if FileManager.default.fileExists(atPath: path) { return path }
            if !path.hasPrefix("/") { return docs + "/" + path }
            if let range = path.range(of: "/Documents/") {
                let relative = String(path[range.upperBound...])
                let fixed = docs + "/" + relative
                if FileManager.default.fileExists(atPath: fixed) { return fixed }
            }
            return path
        }
    }
}
