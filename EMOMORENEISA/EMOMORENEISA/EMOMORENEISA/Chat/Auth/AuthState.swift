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

    /// True when the user is signed in but has not yet completed the voice
    /// onboarding quiz. Drives the full-screen gate from `ModeSelectorView`.
    var needsOnboarding: Bool {
        guard isSignedIn else { return false }
        guard let p = profile else { return false }
        return p.onboardingProfile == nil
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
