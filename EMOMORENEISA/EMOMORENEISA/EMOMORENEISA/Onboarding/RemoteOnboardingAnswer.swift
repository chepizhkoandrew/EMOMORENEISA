import Foundation

/// Mirrors a single confirmed onboarding-quiz answer to Supabase the moment
/// the user confirms it (see `OnboardingCoordinator.confirmAndAdvance()`),
/// not just at the very end of the quiz. Users who drop off partway through
/// (very common for an 11-question voice flow) otherwise leave zero trace —
/// this makes every answer durable as soon as it's given.
struct RemoteOnboardingAnswer: Codable {
    var userId: UUID
    var slot: String
    var transcript: String
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId     = "user_id"
        case slot
        case transcript
        case recordedAt = "recorded_at"
    }
}
