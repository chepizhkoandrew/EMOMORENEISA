import Foundation
import GoogleSignIn
import Supabase
import Auth

final class AuthService {
    static let shared = AuthService()
    private init() {}

    @MainActor
    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        await AuthState.shared.restoreSession()
        if AuthState.shared.profile == nil {
            try await createProfile(for: session.user, displayName: displayName)
        }
    }

    @MainActor
    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }
        let accessToken = result.user.accessToken.tokenString

        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )

        await AuthState.shared.restoreSession()

        if AuthState.shared.profile == nil {
            try await createProfile(for: session.user, displayName: nil)
        }
    }

    private func createProfile(for user: User, displayName: String?) async throws {
        let name = displayName
            ?? user.userMetadata["full_name"]?.value as? String
            ?? user.email
            ?? "Student"
        let profile = ESPProfile(
            id: user.id,
            displayName: name,
            level: "beginner",
            nativeLanguage: "English",
            focusTopics: [],
            currentStudyTopic: nil,
            learningNotes: "",
            sessionCount: 0,
            messageCount: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await supabase
            .from("profiles")
            .insert(profile)
            .execute()
        await AuthState.shared.loadProfile()
    }
}

enum AuthError: LocalizedError {
    case missingIDToken
    var errorDescription: String? {
        switch self {
        case .missingIDToken: return "Google Sign-In did not return an ID token."
        }
    }
}
