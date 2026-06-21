import SwiftUI
import GoogleSignIn
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var currentNonce: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    Text("¡Hola!")
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 16)

                    Text("PROFESSOR MADRID")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(3)
                }

                Spacer().frame(height: 48)

                Text("Sign in to save your progress\nand continue your Spanish journey.")
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 48)

                if isLoading {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(1.4)
                } else {
                    VStack(spacing: 14) {
                        SignInWithAppleButton(.signIn) { request in
                            let nonce = randomNonceString()
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = sha256(nonce)
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 32)

                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                Text("Continue with Google")
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 32)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                }

                if !isLoading {
                    consentNotice
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                }

                Spacer()
            }
        }
    }

    private var consentNotice: some View {
        let terms = "https://professormadrid.com/terms"
        let privacy = "https://professormadrid.com/privacy"
        let text = try? AttributedString(
            markdown: "By continuing, you agree to our [Terms & Conditions](\(terms)) and [Privacy Policy](\(privacy))."
        )
        return Text(text ?? "By continuing, you agree to our Terms & Conditions and Privacy Policy.")
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.45))
            .tint(.yellow)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Apple Sign-In failed: missing credential."
                return
            }
            let displayName: String? = {
                guard let fn = credential.fullName else { return nil }
                let parts = [fn.givenName, fn.familyName].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await AuthService.shared.signInWithApple(idToken: idToken, nonce: nonce, displayName: displayName)
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await AuthService.shared.signInWithGoogle(presenting: rootVC)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
