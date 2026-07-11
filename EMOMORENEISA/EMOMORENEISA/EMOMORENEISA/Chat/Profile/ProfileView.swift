import SwiftUI
import Auth
import SwiftData

struct ProfileView: View {
    var onBack: (() -> Void)? = nil
    @Environment(AuthState.self) private var authState
    @State private var editingLevel: StudentLevel = .beginner
    @State private var editingFocus: String = ""
    @State private var editingPronoun: UserPronoun = .they
    @State private var isSaving = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String? = nil
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true
    @AppStorage("stats.verbGamesPlayed") private var verbGamesPlayed: Int = 0
    @State private var wallet = WalletManager.shared
    @State private var loc = LocalizationManager.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalChatSession.updatedAt, order: .reverse) private var sessions: [LocalChatSession]

    private var profile: ESPProfile? { authState.profile }

    private var memoryService: MemoryCardService { MemoryCardService(context: modelContext) }
    private var totalMessages: Int { sessions.reduce(0) { $0 + $1.messageCount } }
    private var photoSessions: Int { sessions.filter { $0.mode == "visual" }.count }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    identitySection
                    treatsSection
                    aboutMeSection
                    languageSection
                    pronounSection
                    voiceSection
                    levelSection
                    focusSection
                    learningNotesSection
                    statsSection
                    Spacer(minLength: 8)
                    signOutSection
                    deleteAccountSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(L("My Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text(L("Back"))
                                .font(.system(size: 17, weight: .regular))
                        }
                        .foregroundColor(.yellow)
                    }
                }
            }
        }
        .onAppear { loadFromProfile() }
        .task { await wallet.refresh() }
        .navigationDestination(isPresented: $wallet.showPaywall) {
            PaywallView()
        }
        .confirmationDialog(L("Sign out?"), isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button(L("Sign Out"), role: .destructive) {
                Task { await authState.signOut() }
            }
        }
        .confirmationDialog(L("Delete your account?"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(L("Delete Account Permanently"), role: .destructive) {
                Task {
                    isDeletingAccount = true
                    deleteError = nil
                    do {
                        try await authState.deleteAccount()
                    } catch {
                        isDeletingAccount = false
                        deleteError = L("Deletion failed. Please try again or contact support-professormadrid@priroda.tech.")
                    }
                }
            }
        } message: {
            Text(L("This will permanently delete your account, all sessions, memory cards, and treat balance. This cannot be undone."))
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(initials)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.displayName?.isEmpty == false ? profile!.displayName! : L("Learner"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(authState.session?.user.email ?? "")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Treats

    private var treatsSection: some View {
        Button {
            wallet.showPaywall = true
        } label: {
            HStack(spacing: 14) {
                Text("🦴")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%d treats", wallet.balanceTreats))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text(L("Tap to top up"))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                Text(L("Get more"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.yellow)
                    .clipShape(Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppColors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Language"))
            HStack(spacing: 2) {
                ForEach(AppLanguage.allCases) { lang in
                    Button { loc.setLanguage(lang) } label: {
                        Text("\(lang.flag)  \(lang.nativeName)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(loc.language == lang ? .black : AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(loc.language == lang ? Color.yellow : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Pronoun

    // Drives gendered grammar everywhere the tutor addresses the user in a
    // gendered language (Ukrainian past-tense endings especially) — see
    // ESPProfile.profileDigest, included in every chat system prompt.
    private var pronounSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Pronoun"))
            HStack(spacing: 2) {
                ForEach(UserPronoun.allCases) { pronoun in
                    Button { editingPronoun = pronoun; saveProfile() } label: {
                        Text("\(pronoun.ukLabel) · \(pronoun.displayLabel)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(editingPronoun == pronoun ? .black : AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(editingPronoun == pronoun ? Color.yellow : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
            Text(L("This shapes how your tutor addresses you — especially gendered endings in Ukrainian."))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Voice"))
            Toggle(isOn: $autoVoiceEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Automatic voice replies"))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text(L("Turn off to save treats — tap a message to hear it on demand."))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .tint(.yellow)
            .padding(16)
            .background(AppColors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var initials: String {
        let name: String
        if let d = profile?.displayName { name = d }
        else if let e = authState.session?.user.email { name = e }
        else { name = "?" }
        let parts = name.components(separatedBy: " ")
        let first = String(parts.first?.prefix(1) ?? "")
        let second = parts.count > 1 ? String(parts[1].prefix(1)) : ""
        return "\(first)\(second)".uppercased()
    }

    // MARK: - Level (multi-axis, server-derived)

    @ViewBuilder
    private var levelSection: some View {
        if let lb = profile?.onboardingProfile?.levelBreakdown {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(L("Learning Level"))
                VStack(alignment: .leading, spacing: 14) {
                    if !lb.currentState.isEmpty {
                        levelRow(title: L("Current state"),
                                 band: lb.overallBand,
                                 note: lb.currentState)
                    }
                    levelRow(title: L("Listening"),
                             band: lb.listening.band,
                             note: lb.listening.note)
                    levelRow(title: L("Speaking"),
                             band: lb.speaking.band,
                             note: lb.speaking.note)
                    levelRow(title: L("Grammar"),
                             band: lb.grammar.band,
                             note: lb.grammar.note)
                    if !lb.goals.isEmpty {
                        Divider().background(AppColors.cardBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Goals"))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColors.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                            ForEach(Array(lb.goals.enumerated()), id: \.offset) { _, g in
                                Text(g)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundColor(AppColors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(L("Learning Level"))
                HStack(spacing: 2) {
                    ForEach(StudentLevel.allCases) { level in
                        Button { editingLevel = level } label: {
                            Text(L(level.displayLabel))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(editingLevel == level ? .black : AppColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(editingLevel == level ? Color.yellow : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                .onChange(of: editingLevel) { _, _ in saveProfile() }
                Text(L("Complete the voice onboarding to unlock a per-skill CEFR read."))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    private func levelRow(title: String, band: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
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
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Current Focus"))
            TextField(L("e.g. subjunctive mood, travel vocabulary"), text: $editingFocus)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .padding(16)
                .background(AppColors.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.inputBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onSubmit { saveProfile() }
        }
    }

    // MARK: - Notes

    private var learningNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Tutor Notes"))
            Text(profile?.learningNotes.isEmpty == false ? profile!.learningNotes : L("No notes yet — your tutor will update this after sessions."))
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                statCell(label: L("Sessions"), value: "\(sessions.count)", icon: "book.closed.fill")
                statCell(label: L("Messages"), value: "\(totalMessages)", icon: "bubble.left.and.bubble.right.fill")
            }
            HStack(spacing: 1) {
                statCell(label: L("Photos Taken"), value: "\(photoSessions)", icon: "camera.fill")
                statCell(label: L("Verb Games"), value: "\(verbGamesPlayed)", icon: "gamecontroller.fill")
            }
            HStack(spacing: 1) {
                statCell(label: L("Words Learning"), value: "\(memoryService.activeLearningCount)", icon: "brain.fill")
                statCell(label: L("Words Learned"), value: "\(memoryService.knownCount)", icon: "checkmark.seal.fill")
            }
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private func statCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.35), radius: 6)
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppColors.cardBackground)
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(L("Sign Out"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.red.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.red.opacity(0.09))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Delete Account

    private var deleteAccountSection: some View {
        VStack(spacing: 8) {
            Button {
                showDeleteConfirm = true
            } label: {
                Group {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(.red.opacity(0.7))
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                            Text(L("Delete My Account"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.red.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isDeletingAccount)

            if let err = deleteError {
                Text(err)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - About me (voice onboarding paraphrase)

    @ViewBuilder
    private var aboutMeSection: some View {
        if let ob = profile?.onboardingProfile {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(L("About me"))
                VStack(alignment: .leading, spacing: 10) {
                    Text(ob.aboutMeUserFacing.isEmpty
                         ? L("Your voice-onboarding summary will appear here.")
                         : ob.aboutMeUserFacing)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !ob.cityFlavor.isEmpty {
                        Text(ob.cityFlavor)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(AppColors.textTertiary)
                            .italic()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(AppColors.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    // MARK: - Data

    private func loadFromProfile() {
        guard let p = profile else { return }
        editingLevel = p.levelEnum
        editingFocus = p.currentStudyTopic ?? ""
        editingPronoun = p.userPronoun.flatMap(UserPronoun.init(rawValue:)) ?? .they
    }

    private func saveProfile() {
        guard var p = profile else { return }
        p.level = editingLevel.rawValue
        p.currentStudyTopic = editingFocus.isEmpty ? nil : editingFocus
        p.userPronoun = editingPronoun.rawValue
        p.updatedAt = Date()
        // Update the in-memory profile immediately (not just Supabase) so a
        // pronoun change takes effect on the very next chat message in this
        // same session — PromptBuilder reads `authState.profile` fresh per
        // message, it doesn't wait for a relaunch/reload.
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }
}
