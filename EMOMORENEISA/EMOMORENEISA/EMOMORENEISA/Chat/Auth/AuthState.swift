import Foundation
import Observation
import Supabase

@Observable
final class AuthState {
    var session: Session? = nil
    var profile: ESPProfile? = nil
    var isLoading: Bool = true

    var isSignedIn: Bool { session != nil }
    var userId: UUID? { session?.user.id }

    /// True when the user is signed in but hasn't finished onboarding —
    /// covers BOTH the feature-tour carousel (`HomeView`) and the voice quiz
    /// (`ModeSelectorView`'s full-screen gate). Backed by a single Supabase
    /// column (`profiles.has_completed_onboarding`) so QA can force either
    /// flow to replay by flipping one field and relaunching.
    var needsOnboarding: Bool {
        guard isSignedIn else { return false }
        guard let p = profile else { return false }
        return !p.hasCompletedOnboarding
    }

    /// True until the user explicitly accepts the standalone AI-data-sharing
    /// disclosure (AIDisclosureView) — gates every signed-in user, new or
    /// existing, ahead of everything else (including the onboarding voice
    /// quiz, which itself sends recordings to Gemini). Apple 5.1.1(i)/
    /// 5.1.2(i) requires this be a dedicated in-app step, not just wording
    /// inside the Terms/Privacy Policy.
    var needsAIDisclosure: Bool {
        guard isSignedIn else { return false }
        guard let p = profile else { return false }
        return p.aiDisclosureAcceptedAt == nil
    }

    static let shared = AuthState()

    private init() {}

    @MainActor
    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            self.session = session
            await loadProfile()
        } catch {
            self.session = nil
        }
        isLoading = false
    }

    @MainActor
    func loadProfile() async {
        guard let uid = userId else { return }
        do {
            let p: ESPProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: uid.uuidString)
                .single()
                .execute()
                .value
            self.profile = p
        } catch {
            self.profile = nil
        }
    }

    @MainActor
    func signOut() async {
        AnalyticsService.shared.track(.signOut)
        try? await supabase.auth.signOut()
        session = nil
        profile = nil
    }

    @MainActor
    func deleteAccount() async throws {
        AnalyticsService.shared.track(.accountDeleted)
        try await ProxyClient.shared.deleteAccount()
        try? await supabase.auth.signOut()
        session = nil
        profile = nil
    }
}
