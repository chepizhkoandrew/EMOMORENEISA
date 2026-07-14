import Foundation
import Supabase

enum AppEvent {
    case signIn(provider: String)
    case signUp(provider: String)
    case signOut
    case accountDeleted
    case sessionCreated(mode: String)
    case paywallShown(balance: Int)
    case paywallDismissed
    case purchaseStarted(productId: String)
    case purchaseCompleted(productId: String, treats: Int)
    case purchaseCancelled(productId: String)
    case parrotSessionStarted
    case srsSessionStarted(cardCount: Int)
    case srsSessionCompleted(cardCount: Int, archived: Int)
    case streetViewPhotoTaken

    var name: String {
        switch self {
        case .signIn:                return "sign_in"
        case .signUp:                return "sign_up"
        case .signOut:               return "sign_out"
        case .accountDeleted:        return "account_deleted"
        case .sessionCreated:        return "session_created"
        case .paywallShown:          return "paywall_shown"
        case .paywallDismissed:      return "paywall_dismissed"
        case .purchaseStarted:       return "purchase_started"
        case .purchaseCompleted:     return "purchase_completed"
        case .purchaseCancelled:     return "purchase_cancelled"
        case .parrotSessionStarted:  return "parrot_session_started"
        case .srsSessionStarted:     return "srs_session_started"
        case .srsSessionCompleted:   return "srs_session_completed"
        case .streetViewPhotoTaken:  return "street_view_photo_taken"
        }
    }

    var properties: [String: String] {
        switch self {
        case .signIn(let p):                              return ["provider": p]
        case .signUp(let p):                              return ["provider": p]
        case .signOut, .accountDeleted, .paywallDismissed,
             .parrotSessionStarted, .streetViewPhotoTaken: return [:]
        case .sessionCreated(let mode):                   return ["mode": mode]
        case .paywallShown(let balance):                  return ["balance": "\(balance)"]
        case .purchaseStarted(let pid):                   return ["product_id": pid]
        case .purchaseCompleted(let pid, let treats):     return ["product_id": pid, "treats": "\(treats)"]
        case .purchaseCancelled(let pid):                 return ["product_id": pid]
        case .srsSessionStarted(let n):                   return ["card_count": "\(n)"]
        case .srsSessionCompleted(let n, let archived):   return ["card_count": "\(n)", "archived": "\(archived)"]
        }
    }
}

final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    func track(_ event: AppEvent) {
        let userId = AuthState.shared.userId
        Task.detached(priority: .utility) {
            let record = AnalyticsRecord(
                id: UUID(),
                userId: userId,
                name: event.name,
                properties: event.properties
            )
            do {
                try await supabase.from("analytics_events").insert(record).execute()
            } catch {
                glog("📊 ANALYTICS", "⚠️ Failed to track \(event.name): \(error.localizedDescription)")
            }
        }
    }
}

private struct AnalyticsRecord: Encodable {
    let id: UUID
    let userId: UUID?
    let name: String
    let properties: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case name
        case properties
    }
}
