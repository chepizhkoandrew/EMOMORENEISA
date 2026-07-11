import SwiftUI

/// Standalone, dedicated disclosure of what's sent to third-party AI
/// services and why — required by Apple 5.1.1(i)/5.1.2(i): explaining this
/// only in the Terms/Privacy Policy is explicitly called out as
/// insufficient, so this is a separate screen, not another bullet point on
/// `SignInView`'s consent checkbox. Gates every signed-in user (see
/// `AuthState.needsAIDisclosure`) ahead of everything else, including the
/// onboarding voice quiz — which itself sends recordings to Gemini.
struct AIDisclosureView: View {
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 16)

                    Text("How Professor Madrid uses AI")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 36)

                VStack(alignment: .leading, spacing: 18) {
                    disclosureRow(
                        icon: "mic.fill",
                        text: L("Your voice recordings are sent to OpenAI to transcribe your speech into text.")
                    )
                    disclosureRow(
                        icon: "speaker.wave.2.fill",
                        text: L("The tutor's spoken replies are generated mainly by Google's text-to-speech service, with OpenAI used only as an automatic backup if Google's service is temporarily unavailable.")
                    )
                    disclosureRow(
                        icon: "camera.fill",
                        text: L("Photos you take in Street View mode are sent to OpenAI to identify and describe what's in them.")
                    )
                    disclosureRow(
                        icon: "text.bubble.fill",
                        text: L("Your chat messages are sent to OpenAI to generate the tutor's responses.")
                    )
                    disclosureRow(
                        icon: "person.fill.questionmark",
                        text: L("Your answers during setup are sent to Google's Gemini AI to personalize your lessons.")
                    )
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 20)

                Text(L("None of this content is stored by these providers beyond processing your request."))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 32)

                if isLoading {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(1.4)
                } else {
                    Button(action: handleAccept) {
                        Text(L("I Understand & Continue"))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 32)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }

                privacyLink
                    .padding(.horizontal, 32)
                    .padding(.top, 20)

                Spacer()
            }
        }
    }

    private func disclosureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.yellow)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyLink: some View {
        let privacy = "https://professormadrid.com/privacy"
        let text = try? AttributedString(
            markdown: L("Full details in our [Privacy Policy](%@).", privacy)
        )
        return Text(text ?? AttributedString(L("Full details in our Privacy Policy.")))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
            .tint(.yellow)
            .multilineTextAlignment(.center)
    }

    private func handleAccept() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await AuthService.shared.acceptAIDisclosure()
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
