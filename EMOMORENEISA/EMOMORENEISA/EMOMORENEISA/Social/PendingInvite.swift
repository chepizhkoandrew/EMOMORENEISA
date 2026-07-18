import Foundation
import Observation

/// Holds a friend-invite token from a universal link until it can be claimed.
///
/// The token arrives via https://professormadrid.com/invite/<token> — possibly
/// before the user has an account, mid-onboarding, or even before the app was
/// installed. It is persisted to UserDefaults so it survives app kill and the
/// whole signup flow; `claimIfPossible()` runs whenever the token or the auth
/// state changes and only clears the token once the server has answered.
@Observable
final class PendingInvite {
    static let shared = PendingInvite()

    enum ClaimOutcome: Equatable {
        case becameFriends(inviterName: String)
        case alreadyFriends(inviterName: String)
        case deadLink
    }

    /// Set after a claim completes; the UI observes this to show a one-shot alert.
    var lastOutcome: ClaimOutcome? = nil

    private static let tokenKey = "pendingInviteToken"
    private var claiming = false

    private(set) var token: String? = UserDefaults.standard.string(forKey: PendingInvite.tokenKey) {
        didSet {
            if let token {
                UserDefaults.standard.set(token, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    private init() {}

    /// Feed any URL the app was opened with; non-invite URLs are ignored.
    func capture(_ url: URL) {
        guard let token = Self.inviteToken(from: url) else { return }
        self.token = token
        Task { await claimIfPossible() }
    }

    /// Extracts the token from https://professormadrid.com/invite/<token>.
    static func inviteToken(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "invite" else { return nil }
        let token = parts[1]
        return token.isEmpty ? nil : token
    }

    /// Claims the stored token if the user is signed in. Safe to call whenever
    /// auth state changes; no-ops when there is nothing to claim. The token is
    /// kept on transport failure so a later retry (next launch/sign-in) works.
    func claimIfPossible() async {
        guard let token, !claiming, AuthState.shared.isSignedIn else { return }
        claiming = true
        defer { claiming = false }

        do {
            let result = try await ProxyClient.shared.claimInvite(token: token)
            self.token = nil
            let name = result.inviterName ?? L("A friend")
            switch result.result {
            case "created": lastOutcome = .becameFriends(inviterName: name)
            case "already_friends": lastOutcome = .alreadyFriends(inviterName: name)
            case "self_invite": lastOutcome = nil
            default: lastOutcome = .deadLink
            }
        } catch {
            // Transport/server error: keep the token for a later retry.
        }
    }
}
