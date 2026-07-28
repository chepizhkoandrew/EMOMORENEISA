import SwiftUI

/// "Level" settings — the graduated 6-stage ladder (Absolute Beginner →
/// Advanced) that governs how much Spanish vs. native language the tutor
/// uses (see `PromptBuilder.languageGuidance`), plus the read-only CEFR
/// skill breakdown from the voice-onboarding quiz, an immersion-mode nudge,
/// and a few learner-experience toggles.
///
/// A *pushable* page for `SettingsHubView`'s NavigationStack (Settings →
/// Level). This is now the single place to edit level — `ProfileView` only
/// shows a compact read-only summary linking here.
struct LevelSettingsView: View {
    @Environment(AuthState.self) private var authState

    private var profile: ESPProfile? { authState.profile }
    private var native: String { LocalizationManager.shared.tutorNativeLanguage }

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                stageSection
                skillBreakdownSection
                immersionSection
                preferencesSection
            }
            .scrollContentBackground(.hidden)
        }
        .tint(.yellow)
        .navigationTitle(L("Level"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Your level (6-stage progress control)

    private var stageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                stageProgressBar
                Text(L(currentStage.displayLabel))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(L(currentStage.tutoringDescription))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        } header: {
            Text(L("Your level"))
        } footer: {
            Text(L("Tap a stage to jump straight to it."))
        }
    }

    private var stageProgressBar: some View {
        HStack(spacing: 3) {
            ForEach(LearnerStage.allCases) { stage in
                Button {
                    saveStage(stage)
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(stage.order <= currentStage.order ? Color.yellow : AppColors.cardBackground)
                        .frame(height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.cardBorder, lineWidth: stage.order <= currentStage.order ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentStage: LearnerStage { profile?.effectiveStage ?? .absoluteBeginner }

    private func saveStage(_ stage: LearnerStage) {
        guard var p = profile else { return }
        p.absoluteBeginnerOverride = false
        p.learnerStage = stage.rawValue
        p.stageProgressCount = 0
        p.level = stage.bridgedLegacyLevel
        p.updatedAt = Date()
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }

    // MARK: - Skill breakdown (read-only CEFR bands)

    @ViewBuilder
    private var skillBreakdownSection: some View {
        Section {
            if let lb = profile?.onboardingProfile?.levelBreakdown {
                VStack(alignment: .leading, spacing: 14) {
                    skillBar(title: L("Listening"), band: lb.listening.band)
                    skillBar(title: L("Speaking"), band: lb.speaking.band)
                    skillBar(title: L("Grammar"), band: lb.grammar.band)
                }
                .padding(.vertical, 4)
            } else {
                Text(L("Complete the voice onboarding to unlock a per-skill CEFR read."))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
        } header: {
            Text(L("Skill breakdown"))
        } footer: {
            Text(L("This CEFR read comes from your voice onboarding and may not always match the stage above — they're independently adjustable."))
        }
    }

    private static let cefrBands = ["A1", "A2", "B1", "B2", "C1", "C2"]

    private func skillBar(title: String, band: String) -> some View {
        let filled = Self.cefrBands.firstIndex(of: band.uppercased()).map { $0 + 1 } ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(band.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.yellow)
                    .clipShape(Capsule())
            }
            HStack(spacing: 3) {
                ForEach(0..<Self.cefrBands.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(i < filled ? Color.yellow : AppColors.cardBackground)
                        .frame(height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppColors.cardBorder, lineWidth: i < filled ? 0 : 1)
                        )
                }
            }
        }
    }

    // MARK: - Spanish immersion

    private var immersionModeBinding: Binding<ImmersionMode> {
        Binding(
            get: { profile?.immersionModeEnum ?? .guided },
            set: { saveImmersionMode($0) }
        )
    }

    private var immersionSection: some View {
        Section {
            Picker(L("Immersion mode"), selection: immersionModeBinding) {
                ForEach(ImmersionMode.allCases) { mode in
                    Text("\(L(mode.displayLabel)) — \(L(mode.description))").tag(mode)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text(L("Spanish immersion"))
        } footer: {
            Text(L("Nudges how much Spanish vs. %@ your tutor uses, without changing your measured level.", native))
        }
    }

    private func saveImmersionMode(_ mode: ImmersionMode) {
        guard var p = profile else { return }
        p.immersionMode = mode.rawValue
        p.updatedAt = Date()
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }

    // MARK: - Preferences (toggles)

    private var absoluteBeginnerBinding: Binding<Bool> {
        Binding(
            get: { profile?.absoluteBeginnerOverride ?? false },
            set: { saveToggle(\.absoluteBeginnerOverride, $0) }
        )
    }
    private var showTranslationsBinding: Binding<Bool> {
        Binding(
            get: { profile?.showInlineTranslations ?? true },
            set: { saveToggle(\.showInlineTranslations, $0) }
        )
    }
    private var autoSuggestBinding: Binding<Bool> {
        Binding(
            get: { profile?.autoSuggestLevelUp ?? true },
            set: { saveToggle(\.autoSuggestLevelUp, $0) }
        )
    }

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            Toggle(L("Absolute beginner mode"), isOn: absoluteBeginnerBinding)
        } header: {
            Text(L("Preferences"))
        } footer: {
            Text(L("Always speak to me almost entirely in %@, regardless of my measured level.", native))
        }

        Section {
            Toggle(L("Show translations inline"), isOn: showTranslationsBinding)
        } footer: {
            Text(L("Show the %@ meaning next to new Spanish words and phrases.", native))
        }

        Section {
            Toggle(L("Suggest when I'm ready to level up"), isOn: autoSuggestBinding)
        } footer: {
            Text(L("Show a banner on Home when you're consistently doing well at your current level."))
        }
    }

    private func saveToggle(_ keyPath: WritableKeyPath<ESPProfile, Bool>, _ value: Bool) {
        guard var p = profile else { return }
        p[keyPath: keyPath] = value
        p.updatedAt = Date()
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }
}
