import SwiftUI
import Auth
import SwiftData

struct ProfileView: View {
    var onBack: (() -> Void)? = nil
    @Environment(AuthState.self) private var authState
    @State private var editingFocus: String = ""
    @State private var isSaving = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String? = nil
    @AppStorage("stats.verbGamesPlayed") private var verbGamesPlayed: Int = 0
    @State private var wallet = WalletManager.shared
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
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(L("Back"))
                                .font(.system(size: 17, weight: .regular, design: .rounded))
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
                    .font(.system(size: 28, design: .rounded))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("%d treats", wallet.balanceTreats))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .contentTransition(.numericText(value: Double(wallet.balanceTreats)))
                        .animation(.snappy(duration: 0.6), value: wallet.balanceTreats)
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

    // MARK: - Level (read-only summary — edited in Settings → Level)

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Learning Level"))
            NavigationLink {
                LevelSettingsView()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(profile?.effectiveStage.displayLabel ?? LearnerStage.absoluteBeginner.displayLabel))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)
                        if let lb = profile?.onboardingProfile?.levelBreakdown, lb.overallBand != "unknown", !lb.overallBand.isEmpty {
                            Text(L("CEFR overall: %@", lb.overallBand))
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    Spacer()
                    Text(L("Manage level"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 11, design: .rounded))
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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        editingFocus = p.currentStudyTopic ?? ""
    }

    private func saveProfile() {
        guard var p = profile else { return }
        p.currentStudyTopic = editingFocus.isEmpty ? nil : editingFocus
        p.updatedAt = Date()
        // Update the in-memory profile immediately (not just Supabase) so a
        // change takes effect on the very next chat message in this same
        // session — PromptBuilder reads `authState.profile` fresh per message,
        // it doesn't wait for a relaunch/reload.
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }
}
