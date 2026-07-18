import SwiftUI
import SwiftData

/// "My Songs" — the music counterpart of `SessionListView` (My Chats), kept
/// deliberately identical in structure and styling: same background, toolbar
/// (back / treats / profile / plus), row cards, and empty state. The plus
/// button opens the two-step create flow; a finished generation persists a
/// `SavedSong`, so it appears here automatically via the query.
struct SongListView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedSong.createdAt, order: .reverse) private var songs: [SavedSong]
    @State private var showCreate = false
    @State private var showProfile = false
    @State private var wallet = WalletManager.shared
    /// Arriving here jumps straight into creating a new song (the happy path)
    /// rather than making the user look at the list and tap plus. Back out of
    /// creation and you land on this list; back out of this list goes home.
    /// Guards against re-triggering on every SwiftUI re-render of this view.
    @State private var didAutoOpenCreate = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if songs.isEmpty {
                    emptyState
                } else {
                    songList
                }
            }
            .navigationTitle(L("My Songs"))
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
                                .font(.system(size: 24, design: .rounded))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCreate) {
                MusicFlowView()
                    .environment(authState)
            }
            .navigationDestination(for: SavedSong.self) { song in
                SongDetailView(saved: song)
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
        }
        .onAppear {
            if !didAutoOpenCreate {
                didAutoOpenCreate = true
                showCreate = true
            }
        }
    }

    private var treatsPill: some View {
        Button {
            wallet.showPaywall = true
        } label: {
            HStack(spacing: 5) {
                Text("🦴")
                    .font(.system(size: 13, design: .rounded))
                Text("\(wallet.balanceTreats)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(wallet.balanceTreats)))
                    .animation(.snappy(duration: 0.6), value: wallet.balanceTreats)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.yellow)
            .clipShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(songs) { song in
                    NavigationLink(value: song) {
                        SongRowView(song: song)
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
            Image(systemName: "music.note.list")
                .font(.system(size: 72, design: .rounded))
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: 10) {
                Text(L("No songs yet"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Text(L("Turn the words you're learning\ninto your first Spanish song."))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            Button {
                showCreate = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L("Create First Song"))
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
}

struct SongRowView: View {
    let song: SavedSong

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
                Text(song.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(song.genre) · \(song.durationSec)s · \(relativeTime)")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                if let sharedBy = song.sharedByName {
                    Text(L("Shared by %@", sharedBy))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.9))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var relativeTime: String {
        let diff = Date().timeIntervalSince(song.createdAt)
        if diff < 3600 { return L("%dm ago", Int(diff / 60)) }
        if diff < 86400 { return L("%dh ago", Int(diff / 3600)) }
        return L("%dd ago", Int(diff / 86400))
    }
}

/// Playback page for a saved song: same visual family as the fresh-generation
/// result card (play orb, karaoke button, lyrics card), rehydrated from disk.
struct SongDetailView: View {
    let saved: SavedSong

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived }, sort: \MemoryCard.createdAt, order: .reverse)
    private var memoryCards: [MemoryCard]

    @State private var song: ProxyClient.MusicSong? = nil
    @State private var missingAudio = false
    @State private var showKaraoke = false
    @State private var showShare = false
    /// Preloaded on appear so pictures are already downloading by the time
    /// the user taps Play, same as the fresh-generation result screen.
    @State private var sceneImages = KaraokeSceneImages()

    var body: some View {
        ZStack {
            GameBackground()
            DreamParticlesView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Text(saved.title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)

                    Text("\(saved.genre) · \(saved.durationSec)s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)

                    if missingAudio {
                        Text(L("This song's audio file is gone from this device."))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 20)
                    } else {
                        // One control: Play means karaoke (pictures + synced
                        // lyrics) — no separate silent-audio preview.
                        Button {
                            showKaraoke = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 96, height: 96)
                                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 36, weight: .heavy))
                                    .foregroundColor(.black)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                    }

                    if !saved.lyrics.isEmpty {
                        LyricsHighlight.highlightedLyrics(
                            saved.lyrics,
                            targets: saved.pickedWords + (song?.scenes.map(\.word) ?? []),
                            baseColor: .white.opacity(0.85),
                            highlightColor: LyricsHighlight.highlightColor
                        )
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(18)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.42)))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .padding(.bottom, 44)
                    }
                }
                .padding(.horizontal, HomeLayout.hPadding)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !missingAudio {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showKaraoke) {
            if let song {
                MusicKaraokeView(
                    song: song,
                    memoryCards: Array(memoryCards),
                    sceneImages: sceneImages,
                    onShare: { showShare = true }
                )
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSongSheet(saved: saved)
        }
        .onAppear {
            song = saved.asMusicSong()
            missingAudio = song == nil
            if let song {
                sceneImages.load(scenes: song.scenes, cards: memoryCards)
            }
        }
    }
}
