import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LocalChatSession.updatedAt, order: .reverse) private var sessions: [LocalChatSession]
    @State private var showNewSession = false
    @State private var showProfile = false
    @State private var navigateToNewSession: LocalChatSession? = nil
    @State private var wallet = WalletManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle(L("Chat Tutor"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        treatsPill
                        Button {
                            showProfile = true
                        } label: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Button {
                            showNewSession = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showNewSession) {
                NewSessionView(onSessionCreated: { session in
                    showNewSession = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        navigateToNewSession = session
                    }
                })
                .environment(authState)
            }
            .navigationDestination(for: LocalChatSession.self) { session in
                ChatView(session: session)
                    .onAppear { BackgroundMusicPlayer.shared.fadeOut(duration: 1.5) }
                    .onDisappear {
                        TTSService.shared.stop()
                        BackgroundMusicPlayer.shared.play()
                    }
            }
            .navigationDestination(item: $navigateToNewSession) { session in
                ChatView(session: session)
                    .onAppear { BackgroundMusicPlayer.shared.fadeOut(duration: 1.5) }
                    .onDisappear {
                        TTSService.shared.stop()
                        BackgroundMusicPlayer.shared.play()
                    }
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
                    .environment(authState)
            }
            .navigationDestination(isPresented: $wallet.showPaywall) {
                PaywallView()
            }
        }
        .task {
            StoreManager.shared.start()
            await wallet.bootstrap()
            await syncSessionsFromRemote()
        }
    }

    private var treatsPill: some View {
        Button {
            wallet.showPaywall = true
        } label: {
            HStack(spacing: 5) {
                Text("🦴")
                    .font(.system(size: 13))
                Text("\(wallet.balanceTreats)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.yellow)
            .clipShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        SessionRowView(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 72))
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: 10) {
                Text(L("No sessions yet"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Text(L("Start your first Spanish lesson\nwith Professor Madrid."))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Button {
                showNewSession = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text(L("Start First Lesson"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .yellow.opacity(0.45), radius: 12, y: 4)
            }
        }
        .padding(.horizontal, 32)
    }

    private func syncSessionsFromRemote() async {
        guard let userId = authState.userId else { return }
        let remote = await SupabaseSyncService.shared.fetchSessions(for: userId)
        let existingIds = Set(sessions.map(\.id))
        for r in remote where !existingIds.contains(r.id) {
            let local = LocalChatSession(id: r.id, userId: r.userId, mode: SessionMode(rawValue: r.mode) ?? .topic, title: r.title, topic: r.topic)
            local.messageCount = r.messageCount
            local.lastMessagePreview = r.lastMessagePreview
            local.lastMessageAt = r.lastMessageAt
            local.isSynced = true
            modelContext.insert(local)
        }
        try? modelContext.save()
    }
}

struct SessionRowView: View {
    let session: LocalChatSession

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(modeColor.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: session.modeEnum.icon)
                    .font(.system(size: 26))
                    .foregroundColor(modeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title ?? session.topic ?? L(session.modeEnum.displayLabel))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(relativeTime)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var modeColor: Color {
        session.modeEnum == .topic ? .yellow : .cyan
    }

    private var relativeTime: String {
        let diff = Date().timeIntervalSince(session.updatedAt)
        if diff < 3600 { return L("%dm ago", Int(diff / 60)) }
        if diff < 86400 { return L("%dh ago", Int(diff / 3600)) }
        return L("%dd ago", Int(diff / 86400))
    }
}
