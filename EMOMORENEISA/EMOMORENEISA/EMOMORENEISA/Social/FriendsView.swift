import SwiftUI

/// Friends hub: incoming invites (accept/decline), the friends list
/// (unfriend/block via context menu), and the invite composer. Presented as a
/// fullScreenCover from the burger menu, mirroring SongListView's structure.
struct FriendsView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.dismiss) private var dismiss

    @State private var lists: ProxyClient.FriendLists? = nil
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showInviteComposer = false
    /// Friend targeted by the destructive confirmation dialog.
    @State private var confirmTarget: ProxyClient.Friend? = nil
    @State private var confirmAction: FriendAction? = nil

    enum FriendAction { case unfriend, block }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if isLoading && lists == nil {
                    ProgressView().tint(.yellow)
                } else if let lists {
                    content(lists)
                } else {
                    failedState
                }
            }
            .navigationTitle(L("Friends"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInviteComposer = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
            }
            .sheet(isPresented: $showInviteComposer, onDismiss: { Task { await reload() } }) {
                InviteComposerSheet()
                    .environment(authState)
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(
                    get: { confirmTarget != nil },
                    set: { if !$0 { confirmTarget = nil; confirmAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(confirmAction == .block ? L("Block") : L("Unfriend"), role: .destructive) {
                    if let target = confirmTarget, let action = confirmAction {
                        Task { await perform(action, on: target) }
                    }
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(confirmAction == .block
                     ? L("They won't be told. They can no longer share songs with you.")
                     : L("They won't be told. Songs they shared stop appearing for you."))
            }
        }
        .task { await reload() }
    }

    private var confirmTitle: String {
        guard let target = confirmTarget else { return "" }
        return confirmAction == .block
            ? L("Block %@?", target.displayName)
            : L("Unfriend %@?", target.displayName)
    }

    // MARK: - Content

    private func content(_ lists: ProxyClient.FriendLists) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !lists.pending.isEmpty {
                    sectionHeader(L("Friend Invites"))
                    ForEach(lists.pending) { invite in
                        pendingRow(invite)
                    }
                }

                if !lists.friends.isEmpty {
                    sectionHeader(L("My Friends"))
                    ForEach(lists.friends) { friend in
                        friendRow(friend)
                    }
                }

                if !lists.outgoing.isEmpty {
                    sectionHeader(L("Waiting for a Reply"))
                    ForEach(lists.outgoing) { friend in
                        outgoingRow(friend)
                    }
                }

                if lists.friends.isEmpty && lists.pending.isEmpty && lists.outgoing.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await reload() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(AppColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    private func avatar(_ name: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.18))
                .frame(width: 44, height: 44)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
        }
    }

    private func friendRow(_ friend: ProxyClient.Friend) -> some View {
        HStack(spacing: 14) {
            avatar(friend.displayName)
            Text(friend.displayName)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contextMenu {
            Button(role: .destructive) {
                confirmTarget = friend
                confirmAction = .unfriend
            } label: {
                Label(L("Unfriend"), systemImage: "person.badge.minus")
            }
            Button(role: .destructive) {
                confirmTarget = friend
                confirmAction = .block
            } label: {
                Label(L("Block"), systemImage: "hand.raised.fill")
            }
        }
    }

    private func pendingRow(_ invite: ProxyClient.Friend) -> some View {
        HStack(spacing: 14) {
            avatar(invite.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(L("wants to be friends"))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            Spacer()
            Button {
                Task { await respond(invite, accept: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppColors.cardBackground))
                    .overlay(Circle().stroke(AppColors.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                Task { await respond(invite, accept: true) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.yellow))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func outgoingRow(_ friend: ProxyClient.Friend) -> some View {
        HStack(spacing: 14) {
            avatar(friend.displayName)
            Text(friend.displayName)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(L("Invited"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 64, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
                .padding(.top, 60)

            VStack(spacing: 10) {
                Text(L("No friends yet"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                Text(L("Invite someone to learn Spanish\ntogether and share your songs."))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Button {
                showInviteComposer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L("Invite a Friend"))
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

    private var failedState: some View {
        VStack(spacing: 16) {
            Text(L("Couldn't load your friends."))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
            Button(L("Try Again")) { Task { await reload() } }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
        }
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        loadFailed = false
        do {
            lists = try await ProxyClient.shared.friends()
        } catch {
            if lists == nil { loadFailed = true }
        }
        isLoading = false
    }

    private func respond(_ invite: ProxyClient.Friend, accept: Bool) async {
        try? await ProxyClient.shared.respondToFriendInvite(friendshipId: invite.friendshipId, accept: accept)
        await reload()
    }

    private func perform(_ action: FriendAction, on friend: ProxyClient.Friend) async {
        switch action {
        case .unfriend:
            try? await ProxyClient.shared.unfriend(friendshipId: friend.friendshipId)
        case .block:
            try? await ProxyClient.shared.blockUser(userId: friend.userId)
        }
        await reload()
    }
}

/// Invite composer: enter an email (existing user → in-app invite; unknown →
/// a link to send along), or grab a personal link. The one-time/reusable
/// toggle is chosen up front, per spec.
struct InviteComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var reusable = false
    @State private var isWorking = false
    @State private var outcome: Outcome? = nil

    enum Outcome: Equatable {
        case invited
        case alreadyFriends
        case link(url: String, forEmail: String?)
        case failed
    }

    private var mode: String { reusable ? "reusable" : "one_time" }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundTop.ignoresSafeArea()

                VStack(spacing: 18) {
                    // Email invite
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Invite by email"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(AppColors.textTertiary)
                        TextField(L("friend@email.com"), text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)
                            .padding(14)
                            .background(AppColors.inputBackground)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.inputBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Toggle(isOn: $reusable) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Reusable link"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                            Text(L("Anyone who joins with it becomes your friend. Off = first person only."))
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .tint(.yellow)
                    .padding(14)
                    .background(AppColors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button {
                        Task { await inviteByEmail() }
                    } label: {
                        Text(L("Send Invite"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow.opacity(emailValid && !isWorking ? 1 : 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!emailValid || isWorking)

                    Button {
                        Task { await personalLink() }
                    } label: {
                        Text(L("Get my invite link"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    .disabled(isWorking)
                    .padding(.top, 2)

                    outcomeView

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(L("Invite a Friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { dismiss() }
                        .foregroundColor(.yellow)
                }
            }
        }
    }

    private var emailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    @ViewBuilder
    private var outcomeView: some View {
        switch outcome {
        case .invited:
            resultCard(
                icon: "paperplane.fill",
                text: L("Invite sent! They'll see it in their app.")
            )
        case .alreadyFriends:
            resultCard(icon: "person.2.fill", text: L("You're already friends!"))
        case .link(let url, let forEmail):
            VStack(spacing: 12) {
                resultCard(
                    icon: "link",
                    text: forEmail == nil
                        ? L("Here's your invite link — send it any way you like.")
                        : L("%@ isn't on Professor Madrid yet. Send them this link to invite them.", forEmail!)
                )
                if let shareURL = URL(string: url) {
                    ShareLink(item: shareURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(L("Share Link"))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        case .failed:
            resultCard(icon: "exclamationmark.triangle.fill", text: L("Something went wrong. Please try again."))
        case nil:
            EmptyView()
        }
    }

    private func resultCard(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func inviteByEmail() async {
        isWorking = true
        outcome = nil
        do {
            let result = try await ProxyClient.shared.inviteFriend(
                email: email.trimmingCharacters(in: .whitespaces),
                mode: mode
            )
            switch result {
            case .invited: outcome = .invited
            case .alreadyFriends: outcome = .alreadyFriends
            case .link(let url): outcome = .link(url: url, forEmail: email.trimmingCharacters(in: .whitespaces))
            }
        } catch {
            outcome = .failed
        }
        isWorking = false
    }

    private func personalLink() async {
        isWorking = true
        outcome = nil
        do {
            let url = try await ProxyClient.shared.createInviteLink(mode: mode)
            outcome = .link(url: url, forEmail: nil)
        } catch {
            outcome = .failed
        }
        isWorking = false
    }
}
