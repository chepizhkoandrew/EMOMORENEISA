import SwiftUI
import GoogleSignIn
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var currentNonce: String? = nil
    @State private var showEmailForm = false
    @State private var emailInput = ""
    @State private var passwordInput = ""
    @State private var isCreatingAccount = false
    @State private var hasAgreedToTerms = false

    var body: some View {
        ZStack {
            GameBackground()
            DreamParticlesView()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .overlay {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    Image("professor_dog")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 140)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                    Spacer().frame(height: 12)

                    VStack(spacing: 8) {
                        Text("¡Hola!")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.5), radius: 16)

                        Text("PROFESSOR MADRID")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))
                            .tracking(3)
                    }

                    Spacer().frame(height: 36)

                    Text(L("Log in or create an account to save your progress\nand continue your Spanish journey."))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 36)

                    if isLoading {
                        ProgressView()
                            .tint(.yellow)
                            .scaleEffect(1.4)
                    } else {
                        VStack(spacing: 18) {
                            consentCheckbox
                                .padding(.horizontal, 32)

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
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .padding(.horizontal, 32)
                                .disabled(!hasAgreedToTerms)
                                .allowsHitTesting(hasAgreedToTerms)
                                .opacity(hasAgreedToTerms ? 1 : 0.4)

                                Button(action: handleGoogleSignIn) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "g.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                        Text(L("Continue with Google"))
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.white.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .padding(.horizontal, 32)
                                .disabled(!hasAgreedToTerms)
                                .opacity(hasAgreedToTerms ? 1 : 0.4)

                                if showEmailForm {
                                    emailFormSection
                                } else {
                                    Button(action: { withAnimation { showEmailForm = true } }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "envelope.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.white)
                                            Text(L("Continue with Email"))
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color.white.opacity(0.12))
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                    }
                                    .padding(.horizontal, 32)
                                    .disabled(!hasAgreedToTerms)
                                    .opacity(hasAgreedToTerms ? 1 : 0.4)
                                }
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
    }

    private var emailFormSection: some View {
        VStack(spacing: 10) {
            Picker("", selection: $isCreatingAccount) {
                Text(L("Log In")).tag(false)
                Text(L("Create Account")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            TextField(L("Email"), text: $emailInput)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            SecureField(L("Password"), text: $passwordInput)
                .textContentType(.password)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: isCreatingAccount ? handleEmailSignUp : handleEmailSignIn) {
                Text(isCreatingAccount ? L("Create Account") : L("Log In"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(emailInput.isEmpty || passwordInput.isEmpty || !hasAgreedToTerms)
            .opacity(emailInput.isEmpty || passwordInput.isEmpty || !hasAgreedToTerms ? 0.5 : 1)

            Button(action: { withAnimation { showEmailForm = false; emailInput = ""; passwordInput = ""; errorMessage = nil; isCreatingAccount = false } }) {
                Text(L("Cancel"))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 32)
    }

    // Explicit affirmative action, not just "continuing implies agreement" —
    // the checkbox icon toggles `hasAgreedToTerms` (which gates every
    // sign-in/sign-up button below); the text is a plain, unwrapped `Text`
    // so its embedded links stay independently tappable rather than being
    // swallowed by a surrounding Button's tap gesture.
    private var consentCheckbox: some View {
        VStack(alignment: .leading, spacing: 10) {
            aiDisclosureText

            HStack(alignment: .top, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { hasAgreedToTerms.toggle() }
                } label: {
                    Image(systemName: hasAgreedToTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundColor(hasAgreedToTerms ? .yellow : .white.opacity(0.4))
                }
                .buttonStyle(.plain)

                consentText
            }
        }
    }

    // Apple Guideline 5.1.1(i)/5.1.2(i): pointing only to the Terms/Privacy
    // pages is explicitly called out as insufficient — the app itself must
    // name the data and the third parties before the user consents.
    private var aiDisclosureText: some View {
        Text(L("To power your lessons, your messages, voice recordings, and photos are sent to OpenAI and Google Gemini."))
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundColor(.white.opacity(0.5))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var consentText: some View {
        let terms = "https://professormadrid.com/terms"
        let privacy = "https://professormadrid.com/privacy"
        let text = try? AttributedString(
            markdown: L("I agree to the [Terms & Conditions](%@) and [Privacy Policy](%@).", terms, privacy)
        )
        return Text(text ?? AttributedString(L("I agree to the Terms & Conditions and Privacy Policy.")))
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundColor(.white.opacity(0.65))
            .tint(.yellow)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = L("Apple Sign-In failed: missing credential.")
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

    private func handleEmailSignIn() {
        guard !emailInput.isEmpty, !passwordInput.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await AuthService.shared.signInWithEmail(email: emailInput, password: passwordInput)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func handleEmailSignUp() {
        guard !emailInput.isEmpty, !passwordInput.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await AuthService.shared.signUpWithEmail(email: emailInput, password: passwordInput)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
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
