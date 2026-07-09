import SwiftUI
import SwiftData

// Root of the onboarding submodule. Owns the OnboardingStore + Coordinator,
// swaps between the silent pre-form and the voice quiz, and — when the quiz
// finishes — persists the OnboardingProfile onto the user's ESPProfile
// (locally + Supabase) before handing back to the caller.

struct OnboardingContainerView: View {
    var onFinished: () -> Void

    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext

    @State private var store = OnboardingStore()
    @State private var coordinator: OnboardingCoordinator? = nil
    @State private var phase: Phase = .preForm
    @State private var persistError: String? = nil

    enum Phase { case preForm, quiz, persisting }

    var body: some View {
        Group {
            switch phase {
            case .preForm:
                PreOnboardingFormView(store: store) {
                    let coord = OnboardingCoordinator(store: store)
                    coordinator = coord
                    // Seed the display name onto the profile immediately so
                    // the tutor already has it if the user drops out mid-quiz.
                    seedDisplayName()
                    phase = .quiz
                }
            case .quiz:
                if let coord = coordinator {
                    OnboardingView(store: store, coordinator: coord) {
                        phase = .persisting
                        Task { await persistAndFinish() }
                    }
                } else {
                    ZStack { GameBackground() }.ignoresSafeArea()
                }
            case .persisting:
                ZStack {
                    GameBackground().ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().tint(.yellow).scaleEffect(1.3)
                        Text(persistError ?? (store.quizLanguage == .uk
                                              ? "Зберігаю твій профіль…"
                                              : "Saving your profile…"))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .onAppear {
            // The onboarding submodule is a fully isolated audio scene:
            // silence the intro-slide voice manager and fade out the ambient
            // background music so nothing competes with Professor Madrid's
            // questions or the user's answers.
            OnboardAudioManager.shared.stop()
            BackgroundMusicPlayer.shared.fadeOut(duration: 0.4)
        }
        .onDisappear {
            // Restore the ambient soundtrack once onboarding is finished /
            // dismissed so the rest of the app sounds normal again.
            BackgroundMusicPlayer.shared.play()
        }
    }

    // MARK: - Persistence

    private func seedDisplayName() {
        guard var p = authState.profile else { return }
        let name = store.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { p.displayName = name }
        if let pronoun = store.pronoun { p.userPronoun = pronoun.rawValue }
        p.updatedAt = Date()
        authState.profile = p
        mirrorToLocal(profile: p)
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }

    private func persistAndFinish() async {
        guard var p = authState.profile else {
            await MainActor.run { onFinished() }
            return
        }
        let ob = store.buildProfile(quizVersion: 3)
        let name = store.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { p.displayName = name }
        if let pronoun = store.pronoun { p.userPronoun = pronoun.rawValue }
        p.onboardingProfile = ob
        // Mirror a couple of the sharper slots into the existing v2 fields so
        // the older tutor plumbing already benefits (lifeNotes / whyLearning /
        // hobbies) without waiting for the profileDigest pass.
        if let ob {
            if !ob.narrativeSummary.isEmpty {
                p.lifeNotes = ob.narrativeSummary
            }
            if !ob.extractedSlots.whySpanish.isEmpty {
                p.whyLearning = ob.extractedSlots.whySpanish
            }
            if !ob.extractedSlots.hobbies.isEmpty {
                let merged = Array(Set(p.hobbies + ob.extractedSlots.hobbies)).prefix(10)
                p.hobbies = Array(merged)
            }
        }
        p.updatedAt = Date()

        await MainActor.run {
            authState.profile = p
            mirrorToLocal(profile: p)
        }
        await SupabaseSyncService.shared.updateProfile(p)
        await MainActor.run { onFinished() }
    }

    private func mirrorToLocal(profile: ESPProfile) {
        let id = profile.id
        let descriptor = FetchDescriptor<LocalStudentProfile>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: profile)
        } else {
            let fresh = LocalStudentProfile(from: profile)
            modelContext.insert(fresh)
        }
        try? modelContext.save()
    }
}
