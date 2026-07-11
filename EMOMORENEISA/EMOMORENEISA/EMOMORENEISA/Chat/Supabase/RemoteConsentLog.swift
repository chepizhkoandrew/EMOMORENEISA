import Foundation

/// One consent acceptance event (Terms & Conditions or Privacy Policy),
/// written the moment a user creates their account. Append-only audit trail
/// — see `consent_log` migration and `AuthService.finalizeNewAccount`.
struct RemoteConsentLog: Codable {
    var userId: UUID
    var document: String
    var version: String
    var acceptedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId     = "user_id"
        case document
        case version
        case acceptedAt = "accepted_at"
    }
}
