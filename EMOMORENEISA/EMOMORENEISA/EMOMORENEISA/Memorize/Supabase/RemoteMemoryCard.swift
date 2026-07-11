import Foundation

/// Lightweight Supabase mirror of a `MemoryCard` for stats and cross-device
/// reconciliation. Mirrors the `RemoteChatSession` snake_case `CodingKeys`
/// pattern. NO `audioSegmentPaths` bytes are ever sent — audio stays on-device
/// (spec §1.2 / §4.2). Paths could be referenced as strings only; omitted here.
struct RemoteMemoryCard: Codable, Identifiable {
    let id: UUID
    var content: String
    var translation: String
    var exposureCount: Int
    var nextDueAt: Date?
    var lastPlayedAt: Date?
    var isArchived: Bool
    var deviceId: String
    var userId: UUID?
    var event: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, content, translation
        case exposureCount = "exposure_count"
        case nextDueAt     = "next_due_at"
        case lastPlayedAt  = "last_played_at"
        case isArchived    = "is_archived"
        case deviceId      = "device_id"
        case userId        = "user_id"
        case event
        case updatedAt     = "updated_at"
    }

    init(card: MemoryCard, event: String? = nil, deviceId: String = RemoteMemoryCard.currentDeviceId, userId: UUID? = nil) {
        self.id = card.id
        self.content = card.content
        self.translation = card.translation
        self.exposureCount = card.exposureCount
        self.nextDueAt = card.nextDueAt
        self.lastPlayedAt = card.lastPlayedAt
        self.isArchived = card.isArchived
        self.deviceId = deviceId
        self.userId = userId
        self.event = event
        self.updatedAt = Date()
    }

    /// Stable per-install device identifier for E13 max-merge reconciliation.
    static let currentDeviceId: String = {
        let key = "loro.memorize.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
}

/// Conflict resolution for multi-device merge (E13): prefer the most-advanced
/// exposure, then the latest play. Spec §1.2 / §18 E13.
enum MemoryCardReconciler {
    nonisolated static func winner(local: RemoteMemoryCard, remote: RemoteMemoryCard) -> RemoteMemoryCard {
        if local.exposureCount != remote.exposureCount {
            return local.exposureCount > remote.exposureCount ? local : remote
        }
        let l = local.lastPlayedAt ?? .distantPast
        let r = remote.lastPlayedAt ?? .distantPast
        return l >= r ? local : remote
    }
}
