import Foundation
import Supabase

/// RLS-scoped reads for the social layer (activity feed, announcements, acks).
/// Mirrors `SupabaseSyncService`: direct PostgREST calls for rows the user owns.
/// Everything that mutates the social graph goes through `ProxyClient` instead.
final class SocialSyncService {
    static let shared = SocialSyncService()
    private init() {}

    // MARK: - Models

    struct ActivityEvent: Decodable, Identifiable {
        let id: UUID
        let actorId: UUID?
        let kind: String
        let payload: Payload
        let readAt: Date?
        let createdAt: Date

        struct Payload: Decodable {
            let actorName: String?
            let songTitle: String?
            let shareId: String?
            let packId: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case actorId = "actor_id"
            case kind
            case payload
            case readAt = "read_at"
            case createdAt = "created_at"
        }
    }

    struct Announcement: Decodable, Identifiable {
        let id: UUID
        let title: String
        let body: String
        let announcedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, title, body
            case announcedAt = "announced_at"
        }
    }

    private struct AckRow: Decodable {
        let announcementId: UUID
        enum CodingKeys: String, CodingKey {
            case announcementId = "announcement_id"
        }
    }

    private struct NewAck: Encodable {
        let announcement_id: UUID
        let user_id: UUID
    }

    // MARK: - Activity feed

    func fetchActivityEvents(userId: UUID, limit: Int = 100) async -> [ActivityEvent] {
        do {
            return try await supabase
                .from("activity_events")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
        } catch {
            glog("👥 SOCIAL", "⚠️ Failed to fetch activity: \(error.localizedDescription)")
            return []
        }
    }

    func unreadActivityCount(userId: UUID) async -> Int {
        do {
            let events: [ActivityEvent] = try await supabase
                .from("activity_events")
                .select()
                .eq("user_id", value: userId.uuidString)
                .is("read_at", value: nil)
                .execute()
                .value
            return events.count
        } catch {
            return 0
        }
    }

    /// Batch mark-read; called when the feed tab appears.
    func markActivityRead(userId: UUID) async {
        do {
            try await supabase
                .from("activity_events")
                .update(["read_at": Date()])
                .eq("user_id", value: userId.uuidString)
                .is("read_at", value: nil)
                .execute()
        } catch {
            glog("👥 SOCIAL", "⚠️ Failed to mark activity read: \(error.localizedDescription)")
        }
    }

    // MARK: - Announcements

    /// Active announcements the user hasn't dismissed yet.
    func fetchAnnouncements(userId: UUID) async -> [Announcement] {
        do {
            let all: [Announcement] = try await supabase
                .from("announcements")
                .select()
                .eq("status", value: "active")
                .order("announced_at", ascending: false)
                .execute()
                .value
            let acks: [AckRow] = try await supabase
                .from("announcement_acks")
                .select("announcement_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            let acked = Set(acks.map(\.announcementId))
            return all.filter { !acked.contains($0.id) }
        } catch {
            glog("👥 SOCIAL", "⚠️ Failed to fetch announcements: \(error.localizedDescription)")
            return []
        }
    }

    func acknowledgeAnnouncement(_ id: UUID, userId: UUID) async {
        do {
            try await supabase
                .from("announcement_acks")
                .upsert(NewAck(announcement_id: id, user_id: userId), onConflict: "announcement_id,user_id")
                .execute()
        } catch {
            glog("👥 SOCIAL", "⚠️ Failed to ack announcement: \(error.localizedDescription)")
        }
    }
}
