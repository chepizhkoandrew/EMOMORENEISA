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
        try? await supabase.auth.signOut()
        session = nil
        profile = nil
    }
}
