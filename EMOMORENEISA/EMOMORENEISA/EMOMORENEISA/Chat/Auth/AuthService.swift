import Foundation
import GoogleSignIn
import Supabase
import Auth
import CryptoKit

final class AuthService {
    static let shared = AuthService()
    private init() {}

    /// Must be bumped in lockstep with the "Last updated" date on the
    /// corresponding page at professormadrid.com whenever its wording
    /// changes — this is what ties a `consent_log` row to a specific
    /// version of the document the user actually saw.
    static let termsVersion = "2026-07-14"
    static let privacyVersion = "2026-07-03"
    static let aiDisclosureVersion = "2026-07-11"

    @MainActor
    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        await AuthState.shared.restoreSession()
        let isNew = isNewAccount(session.user)
        if isNew {
            // Apple only ever hands us the user's real name on this very
            // first authorization — the trigger-created row falls back to
            // email/"Student", so patch in the real name when we have it.
            try await finalizeNewAccount(for: session.user, displayName: displayName)
        }
        AnalyticsService.shared.track(isNew ? .signUp(provider: "apple") : .signIn(provider: "apple"))
    }

    @MainActor
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        // Supabase's GoTrue always verifies sha256(nonce we pass it) against
        // the id_token's nonce claim — regardless of provider. Apple's flow
        // already gets this right: hash goes to the provider, raw value goes
        // to Supabase. The first fix here sent the RAW nonce to Google
        // (expecting it embedded verbatim), which fixed the earlier "must
        // both exist or neither" error but left sha256(raw) != raw in the
        // token, i.e. "Nonces Mismatch". This mirrors Apple exactly instead.
        let nonce = randomNonceString()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: nil,
            additionalScopes: nil,
            nonce: sha256(nonce)
        )
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }
        let accessToken = result.user.accessToken.tokenString

        let session: Session
        do {
            session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nonce)
            )
        } catch {
            print("[AUTH] Google signInWithIdToken failed: \(error)")
            throw error
        }

        await AuthState.shared.restoreSession()

        let isNew = isNewAccount(session.user)
        if isNew {
            try await finalizeNewAccount(for: session.user, displayName: nil)
        }
        AnalyticsService.shared.track(isNew ? .signUp(provider: "google") : .signIn(provider: "google"))
    }

    @MainActor
    func signInWithEmail(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        await AuthState.shared.restoreSession()
        let isNew = isNewAccount(session.user)
        if isNew {
            try await finalizeNewAccount(for: session.user, displayName: nil)
        }
        AnalyticsService.shared.track(isNew ? .signUp(provider: "email") : .signIn(provider: "email"))
    }

    @MainActor
    func signUpWithEmail(email: String, password: String) async throws {
        let response = try await supabase.auth.signUp(email: email, password: password)
        guard case .session(let session) = response else {
            // Project has "confirm email" enabled — no session yet, nothing to sign in to.
            throw AuthError.emailConfirmationRequired
        }
        await AuthState.shared.restoreSession()
        try await finalizeNewAccount(for: session.user, displayName: nil)
        AnalyticsService.shared.track(.signUp(provider: "email"))
    }

    /// True when `auth.users` created this account moments ago — the trigger
    /// that creates the matching `profiles` row runs in the SAME transaction
    /// as account creation, so `AuthState.profile == nil` is no longer a
    /// valid "is this new" signal (a profile now always exists). Recency of
    /// `createdAt` is the replacement signal.
    private func isNewAccount(_ user: User) -> Bool {
        Date().timeIntervalSince(user.createdAt) < 10
    }

    /// The `profiles` row itself is guaranteed to already exist by now (see
    /// `20260710000000_auto_create_profile_trigger.sql`) — this only patches
    /// in a better display name when the provider handed us one the trigger
    /// couldn't have seen (Apple's real name, client-side only, one-time),
    /// and logs the consent this is the user's very first account.
    private func finalizeNewAccount(for user: User, displayName: String?) async throws {
        if let name = displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            try await supabase
                .from("profiles")
                .update(["display_name": name])
                .eq("id", value: user.id.uuidString)
                .execute()
        }
        await AuthState.shared.loadProfile()
        logConsent(for: user.id)
    }

    /// Called once, at the moment a brand-new account is created — the UI
    /// gates every sign-in/sign-up button behind an explicit "I agree"
    /// checkbox (see `SignInView`), so reaching here means the user actively
    /// consented, not just continued past a passive notice.
    private func logConsent(for userId: UUID) {
        let now = Date()
        let entries = [
            RemoteConsentLog(userId: userId, document: "terms", version: Self.termsVersion, acceptedAt: now),
            RemoteConsentLog(userId: userId, document: "privacy", version: Self.privacyVersion, acceptedAt: now)
        ]
        Task.detached {
            for entry in entries {
                await SupabaseSyncService.shared.insertConsentLog(entry)
            }
        }
    }

    /// Called from `AIDisclosureView`'s "I Understand & Continue" button —
    /// unlike `logConsent`, this fires for EVERY signed-in user (not just
    /// brand-new signups), since existing accounts created before this
    /// screen existed also need to see and explicitly accept it. Throws (and
    /// leaves the gate up) if the write fails, rather than silently letting
    /// the user through without a recorded acceptance.
    @MainActor
    func acceptAIDisclosure() async throws {
        guard let userId = AuthState.shared.userId else { return }
        let now = Date()
        try await supabase
            .from("profiles")
            .update(["ai_disclosure_accepted_at": now])
            .eq("id", value: userId.uuidString)
            .execute()
        await AuthState.shared.loadProfile()
        let entry = RemoteConsentLog(userId: userId, document: "ai_data_sharing", version: Self.aiDisclosureVersion, acceptedAt: now)
        Task.detached {
            await SupabaseSyncService.shared.insertConsentLog(entry)
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum AuthError: LocalizedError {
    case missingIDToken
    case emailConfirmationRequired
    var errorDescription: String? {
        switch self {
        case .missingIDToken: return "Google Sign-In did not return an ID token."
        case .emailConfirmationRequired: return "Check your email to confirm your account, then log in."
        }
    }
}
