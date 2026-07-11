import Foundation
import Supabase

final class SupabaseSyncService {
    static let shared = SupabaseSyncService()
    private init() {}

    func upsertSession(_ session: LocalChatSession, userId: UUID) async {
        let remote = RemoteChatSession(
            id: session.id,
            userId: userId,
            mode: session.mode,
            title: session.title,
            topic: session.topic,
            sessionGoal: session.sessionGoal,
            messageCount: session.messageCount,
            lastMessagePreview: session.lastMessagePreview,
            lastMessageAt: session.lastMessageAt,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
        do {
            try await supabase.from("sessions").upsert(remote).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to sync session \(session.id): \(error.localizedDescription)")
        }
    }

    func insertMessage(_ message: LocalChatMessage) async {
        let remote = RemoteChatMessage(
            id: message.id,
            sessionId: message.sessionId,
            threadParentId: message.threadParentId,
            sender: message.sender,
            type: message.type,
            textContent: message.textContent,
            rawTranscript: message.rawTranscript,
            audioStoragePath: nil,
            imageStoragePaths: message.imageLocalPaths,
            isEnhanced: message.isEnhanced,
            threadReplyCount: message.threadReplyCount,
            createdAt: message.createdAt
        )
        do {
            try await supabase.from("messages").insert(remote).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to sync message \(message.id): \(error.localizedDescription)")
        }
    }

    func updateProfile(_ profile: ESPProfile) async {
        do {
            try await supabase
                .from("profiles")
                .update(profile)
                .eq("id", value: profile.id.uuidString)
                .execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to update profile: \(error.localizedDescription)")
        }
    }

    func fetchSessions(for userId: UUID) async -> [RemoteChatSession] {
        do {
            return try await supabase
                .from("sessions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .execute()
                .value
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to fetch sessions: \(error.localizedDescription)")
            return []
        }
    }

    func fetchMessages(for sessionId: UUID) async -> [RemoteChatMessage] {
        do {
            return try await supabase
                .from("messages")
                .select()
                .eq("session_id", value: sessionId.uuidString)
                .is("thread_parent_id", value: nil)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to fetch messages: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Onboarding quiz (per-answer capture, not just the final synthesis)

    func upsertOnboardingAnswer(_ answer: RemoteOnboardingAnswer) async {
        do {
            try await supabase
                .from("onboarding_answers")
                .upsert(answer, onConflict: "user_id,slot")
                .execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to sync onboarding answer \(answer.slot): \(error.localizedDescription)")
        }
    }

    // MARK: - Consent audit trail

    func insertConsentLog(_ log: RemoteConsentLog) async {
        do {
            try await supabase.from("consent_log").insert(log).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to log consent (\(log.document)): \(error.localizedDescription)")
        }
    }

    // MARK: - Verb game (per-word attempt capture)

    func upsertVerbAttempt(_ attempt: RemoteVerbAttempt) async {
        do {
            try await supabase.from("verb_attempts").upsert(attempt).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to sync verb attempt \(attempt.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Loro Memorize (stats mirror only — no audio bytes)

    func upsertMemoryCard(_ card: RemoteMemoryCard) async {
        do {
            try await supabase.from("memory_cards").upsert(card).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to sync memory card \(card.id): \(error.localizedDescription)")
        }
    }

    func fetchMemoryCards(for deviceId: String) async -> [RemoteMemoryCard] {
        do {
            return try await supabase
                .from("memory_cards")
                .select()
                .eq("device_id", value: deviceId)
                .execute()
                .value
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to fetch memory cards: \(error.localizedDescription)")
            return []
        }
    }

    func fetchMemoryCards(for userId: UUID) async -> [RemoteMemoryCard] {
        do {
            return try await supabase
                .from("memory_cards")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to fetch memory cards: \(error.localizedDescription)")
            return []
        }
    }

    func insertAnalystEvent(_ event: RemoteAnalystEvent) async {
        do {
            try await supabase.from("analyst_events").insert(event).execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to insert analyst event: \(error.localizedDescription)")
        }
    }

    func updateProfileV2(_ profile: ESPProfile) async {
        let update = ProfileV2Update(
            wordBank: profile.wordBank,
            phraseBank: profile.phraseBank,
            errorLog: profile.errorLog,
            weakAreas: profile.weakAreas,
            masteredAreas: profile.masteredAreas,
            lifeNotes: profile.lifeNotes,
            hobbies: profile.hobbies,
            exerciseHistory: profile.exerciseHistory,
            updatedAt: profile.updatedAt
        )
        do {
            try await supabase
                .from("profiles")
                .update(update)
                .eq("id", value: profile.id.uuidString)
                .execute()
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to update profile v2: \(error.localizedDescription)")
        }
    }

    func fetchThreadMessages(parentId: UUID) async -> [RemoteChatMessage] {
        do {
            return try await supabase
                .from("messages")
                .select()
                .eq("thread_parent_id", value: parentId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            glog("☁️ SYNC  ", "⚠️ Failed to fetch thread messages: \(error.localizedDescription)")
            return []
        }
    }
}
