import SwiftUI
import SwiftData

/// Share a saved song with friends (multi-select) and/or a typed email.
/// Sharing is free. Emails without an account still get a share reference
/// (it materializes when they onboard) plus an invite link to send along.
/// Also exports the song as a 9:16 karaoke video for Instagram & co.
struct ShareSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let saved: SavedSong

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived }, sort: \MemoryCard.createdAt, order: .reverse)
    private var memoryCards: [MemoryCard]

    @State private var friends: [ProxyClient.Friend] = []
    @State private var selected: Set<String> = []
    @State private var email = ""
    @State private var isLoadingFriends = true
    @State private var isSending = false
    @State private var didSend = false
    @State private var failed = false
    @State private var inviteLinks: [(email: String, url: String)] = []

    // Video export
    @State private var sceneImages = KaraokeSceneImages()
    @State private var exportProgress: Double? = nil
    @State private var exportedVideoURL: URL? = nil
    @State private var exportFailed = false

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
                        videoSection
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

    // MARK: - Video clip

    @ViewBuilder
    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Post it anywhere"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)

            if let url = exportedVideoURL {
                ShareLink(item: url, preview: SharePreview(saved.title)) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(L("Share Video"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else if let progress = exportProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.yellow)
                    Text(L("Rendering your karaoke video…"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.vertical, 6)
            } else {
                Button {
                    Task { await exportVideo() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(L("Create Video Clip"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Text(L("A karaoke video with pictures and synced lyrics — ready for Instagram, TikTok, or your camera roll."))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }

            if exportFailed {
                Text(L("Video export failed. Please try again."))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
        .padding(.top, 6)
    }

    private func exportVideo() async {
        guard let song = saved.asMusicSong() else {
            exportFailed = true
            return
        }
        exportFailed = false
        exportProgress = 0

        // Pictures may not be downloaded yet on this screen — kick the same
        // progressive loader karaoke uses and wait for it to finish.
        sceneImages.load(scenes: song.scenes, cards: Array(memoryCards))
        await sceneImages.waitUntilLoaded()

        let input = KaraokeVideoExporter.makeInput(
            song: song,
            images: sceneImages.images,
            highlightTargets: saved.pickedWords + song.scenes.map(\.word)
        )
        do {
            let url = try await KaraokeVideoExporter.export(input) { p in
                Task { @MainActor in exportProgress = p }
            }
            exportedVideoURL = url
        } catch {
            exportFailed = true
        }
        exportProgress = nil
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
