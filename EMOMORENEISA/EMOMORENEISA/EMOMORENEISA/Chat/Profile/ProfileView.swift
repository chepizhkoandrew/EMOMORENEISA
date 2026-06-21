import SwiftUI
import Auth

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @State private var editingLevel: StudentLevel = .beginner
    @State private var editingFocus: String = ""
    @State private var isSaving = false
    @State private var showSignOutConfirm = false
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true
    @State private var wallet = WalletManager.shared
    @Environment(\.dismiss) private var dismiss

    private var profile: ESPProfile? { authState.profile }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    identitySection
                    treatsSection
                    voiceSection
                    levelSection
                    focusSection
                    learningNotesSection
                    statsSection
                    Spacer(minLength: 8)
                    signOutSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(.yellow)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
        }
        .onAppear { loadFromProfile() }
        .task { await wallet.refresh() }
        .sheet(isPresented: $wallet.showPaywall) {
            PaywallView()
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await authState.signOut() }
            }
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
                Text(profile?.displayName?.isEmpty == false ? profile!.displayName! : "Learner")
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
                    Text("\(wallet.balanceTreats) treats")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Tap to top up")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                Text("Get more")
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

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Voice")
            Toggle(isOn: $autoVoiceEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic voice replies")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Turn off to save treats — tap a message to hear it on demand.")
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

    // MARK: - Level

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Learning Level")
            Picker("Level", selection: $editingLevel) {
                ForEach(StudentLevel.allCases) { level in
                    Text(level.displayLabel).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(.yellow)
            .frame(maxWidth: .infinity)
            .onChange(of: editingLevel) { _, _ in saveProfile() }
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Current Focus")
            TextField("e.g. subjunctive mood, travel vocabulary", text: $editingFocus)
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
            sectionHeader("Tutor Notes")
            Text(profile?.learningNotes.isEmpty == false ? profile!.learningNotes : "No notes yet — your tutor will update this after sessions.")
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
        HStack(spacing: 0) {
            statCell(label: "Sessions", value: "\(profile?.sessionCount ?? 0)", icon: "book.closed.fill")
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 50)
            statCell(label: "Messages", value: "\(profile?.messageCount ?? 0)", icon: "bubble.left.and.bubble.right.fill")
        }
        .padding(.vertical, 20)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private func statCell(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.yellow)
                .shadow(color: .yellow.opacity(0.35), radius: 6)
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text("Sign Out")
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
    }

    private func saveProfile() {
        guard var p = profile else { return }
        p.level = editingLevel.rawValue
        p.currentStudyTopic = editingFocus.isEmpty ? nil : editingFocus
        p.updatedAt = Date()
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }
}
