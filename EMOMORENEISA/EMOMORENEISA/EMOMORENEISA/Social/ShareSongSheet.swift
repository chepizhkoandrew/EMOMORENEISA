import SwiftUI

/// Share a saved song with friends (multi-select) and/or a typed email.
/// Sharing is free. Emails without an account still get a share reference
/// (it materializes when they onboard) plus an invite link to send along.
struct ShareSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let saved: SavedSong

    @State private var friends: [ProxyClient.Friend] = []
    @State private var selected: Set<String> = []
    @State private var email = ""
    @State private var isLoadingFriends = true
    @State private var isSending = false
    @State private var didSend = false
    @State private var failed = false
    @State private var inviteLinks: [(email: String, url: String)] = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundTop.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        if didSend {
                            sentView
                        } else {
                            pickerView
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("Share Song"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { dismiss() }
                        .foregroundColor(.yellow)
                }
            }
        }
        .task {
            friends = (try? await ProxyClient.shared.friends())?.friends ?? []
            isLoadingFriends = false
        }
    }

    // MARK: - Picker

    @ViewBuilder
    private var pickerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 22, design: .rounded))
                .foregroundColor(.yellow)
            Text(saved.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
            Spacer()
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))

        if isLoadingFriends {
            ProgressView().tint(.yellow).padding(.vertical, 8)
        } else if !friends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Send to friends"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(friends) { friend in
                    Button {
                        if selected.contains(friend.userId) {
                            selected.remove(friend.userId)
                        } else {
                            selected.insert(friend.userId)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(friend.userId)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, design: .rounded))
                                .foregroundColor(selected.contains(friend.userId) ? .yellow : AppColors.textTertiary)
                            Text(friend.displayName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppColors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                            selected.contains(friend.userId) ? Color.yellow.opacity(0.5) : AppColors.cardBorder,
                            lineWidth: 1
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(L("Or send to an email"))
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
            Text(L("If they don't have the app yet, the song will be waiting when they join."))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        }

        if failed {
            Text(L("Something went wrong. Please try again."))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.red.opacity(0.85))
        }

        Button {
            Task { await send() }
        } label: {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Text(L("Share"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.yellow.opacity(canSend && !isSending ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canSend || isSending)
    }

    private var canSend: Bool {
        !selected.isEmpty || emailValid
    }

    private var emailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    // MARK: - Sent

    @ViewBuilder
    private var sentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, design: .rounded))
                .foregroundColor(.yellow)
                .padding(.top, 24)
            Text(L("Song shared!"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
            if inviteLinks.isEmpty {
                Text(L("Your friends will see it in their app — free for them."))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }

        ForEach(inviteLinks, id: \.email) { link in
            VStack(alignment: .leading, spacing: 10) {
                Text(L("%@ isn't on Professor Madrid yet. Send them this invite so they can hear it.", link.email))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: link.url) {
                    ShareLink(item: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(L("Share Invite Link"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(14)
            .background(AppColors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Action

    private func send() async {
        guard let song = saved.asMusicSong() else {
            failed = true
            return
        }
        isSending = true
        failed = false
        do {
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            inviteLinks = try await ProxyClient.shared.shareSong(
                sourceSongId: saved.id.uuidString,
                title: saved.title,
                genre: saved.genre,
                durationSec: saved.durationSec,
                lyrics: saved.lyrics,
                lines: song.lines,
                scenes: song.scenes,
                audioData: song.audioData,
                friendUserIds: Array(selected),
                emails: emailValid ? [trimmed] : []
            )
            didSend = true
        } catch {
            failed = true
        }
        isSending = false
    }
}
