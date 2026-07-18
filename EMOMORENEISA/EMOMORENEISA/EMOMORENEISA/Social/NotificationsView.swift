import SwiftUI

/// Notifications hub — three tabs:
///   Friends: the activity feed (song shared with you, friend invites/accepts,
///            friend bought a pack).
///   Shared:  running history of every song ever shared with you, claimed or not.
///   App:     admin announcements; Dismiss inserts an ack so it never reappears.
struct NotificationsView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case friends, shared, app
        var title: String {
            switch self {
            case .friends: return L("Friends")
            case .shared: return L("Shared with You")
            case .app: return L("App News")
            }
        }
    }

    @State private var tab: Tab = .friends
    @State private var events: [SocialSyncService.ActivityEvent] = []
    @State private var announcements: [SocialSyncService.Announcement] = []
    @State private var shares: [ProxyClient.SharedSongItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 14) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Text(t.title).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)

                    if isLoading {
                        Spacer()
                        ProgressView().tint(.yellow)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                switch tab {
                                case .friends: friendsFeed
                                case .shared: sharedFeed
                                case .app: appFeed
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .refreshable { await reload() }
                    }
                }
            }
            .navigationTitle(L("Notifications"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
        .task { await reload() }
        .onChange(of: tab) { _, newTab in
            if newTab == .friends { Task { await markRead() } }
        }
    }

    // MARK: - Friends' activities

    @ViewBuilder
    private var friendsFeed: some View {
        if events.isEmpty {
            emptyCard(icon: "person.2.fill", text: L("Nothing from your friends yet.\nInvite someone to get started!"))
        } else {
            ForEach(events) { event in
                eventRow(event)
            }
        }
    }

    private func eventRow(_ event: SocialSyncService.ActivityEvent) -> some View {
        let name = event.payload.actorName ?? L("A friend")
        let (icon, text): (String, String) = {
            switch event.kind {
            case "song_shared":
                return ("music.note", L("%@ shared a song with you: “%@”", name, event.payload.songTitle ?? ""))
            case "friend_invite":
                return ("person.badge.plus", L("%@ wants to be your friend", name))
            case "friend_accepted":
                return ("person.2.fill", L("%@ accepted your invite — you're friends now!", name))
            case "treat_pack_purchased":
                return ("gift.fill", L("%@ bought a treat pack", name))
            default:
                return ("bell.fill", name)
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(relativeTime(event.createdAt))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            Spacer()
            if event.readAt == nil {
                Circle().fill(Color.yellow).frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Shared with you

    @ViewBuilder
    private var sharedFeed: some View {
        if shares.isEmpty {
            emptyCard(icon: "music.note.list", text: L("No songs have been shared with you yet."))
        } else {
            ForEach(shares) { share in
                SharedSongRow(share: share) {
                    Task { await reload() }
                }
            }
        }
    }

    // MARK: - App announcements

    @ViewBuilder
    private var appFeed: some View {
        if announcements.isEmpty {
            emptyCard(icon: "bell.fill", text: L("No news right now — you're all caught up!"))
        } else {
            ForEach(announcements) { a in
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Text(a.body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            if let uid = authState.userId {
                                await SocialSyncService.shared.acknowledgeAnnouncement(a.id, userId: uid)
                                announcements.removeAll { $0.id == a.id }
                            }
                        }
                    } label: {
                        Text(L("Got it"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppColors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Shared bits

    private func emptyCard(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return L("%dm ago", max(1, Int(diff / 60))) }
        if diff < 86400 { return L("%dh ago", Int(diff / 3600)) }
        return L("%dd ago", Int(diff / 86400))
    }

    private func reload() async {
        guard let uid = authState.userId else { isLoading = false; return }
        async let e = SocialSyncService.shared.fetchActivityEvents(userId: uid)
        async let a = SocialSyncService.shared.fetchAnnouncements(userId: uid)
        events = await e
        announcements = await a
        shares = (try? await ProxyClient.shared.sharedSongs()) ?? []
        isLoading = false
        if tab == .friends { await markRead() }
    }

    private func markRead() async {
        guard let uid = authState.userId else { return }
        guard events.contains(where: { $0.readAt == nil }) else { return }
        await SocialSyncService.shared.markActivityRead(userId: uid)
    }
}

/// One row in "Shared with You": download-to-library for unclaimed items,
/// a checkmark for already-claimed ones.
struct SharedSongRow: View {
    @Environment(\.modelContext) private var modelContext
    let share: ProxyClient.SharedSongItem
    var onChanged: () -> Void

    @State private var isDownloading = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: "music.note")
                    .font(.system(size: 26, design: .rounded))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(share.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                Text(L("Shared by %@", share.sharedByName))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if share.claimed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, design: .rounded))
                    .foregroundColor(.yellow.opacity(0.7))
            } else if isDownloading {
                ProgressView().tint(.yellow)
            } else {
                Button {
                    Task { await download() }
                } label: {
                    Image(systemName: failed ? "arrow.clockwise" : "arrow.down.circle.fill")
                        .font(.system(size: 26, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func download() async {
        isDownloading = true
        failed = false
        do {
            let result = try await ProxyClient.shared.downloadSharedSong(shareId: share.shareId)
            let saved = await SavedSong.persist(
                result.song,
                in: modelContext,
                sharedByName: result.sharedByName,
                sharedFromUserId: result.sharerId,
                shareId: share.shareId
            )
            if saved == nil { failed = true } else { onChanged() }
        } catch {
            failed = true
        }
        isDownloading = false
    }
}
