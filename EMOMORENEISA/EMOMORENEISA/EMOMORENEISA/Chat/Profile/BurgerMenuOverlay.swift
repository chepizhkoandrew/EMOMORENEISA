import SwiftUI

/// A single caller-supplied row shown above "Your Chats" and "Profile" in the
/// burger sheet. `label` is a raw (unlocalized) key — the sheet wraps it in
/// `L(...)` at render time, matching how every other screen in the app
/// localizes at the call site.
struct BurgerMenuItem: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let action: () -> Void
}

/// Reusable burger-menu entry point: a top-right hamburger button that opens
/// a sheet listing "Your Chats", "Profile", and any screen-specific extra
/// rows. Mirrors `ProfileButtonOverlay`'s self-contained state pattern — each
/// usage owns its own presentation state, so nothing leaks between screens.
struct BurgerMenuOverlay: ViewModifier {
    @Environment(AuthState.self) private var authState
    @State private var showMenu = false
    @State private var showChats = false
    @State private var showSongs = false
    @State private var showProfile = false
    @State private var showSettings = false
    @State private var showFriends = false
    @State private var showNotifications = false
    /// Fires `true` right as any of this modifier's own destinations is
    /// about to cover the host screen, `false` once every one of them is
    /// dismissed again. A host with its own ambient audio/animation (e.g.
    /// ModeSelectorView's speaking dog) needs this because presenting a
    /// `fullScreenCover` does NOT trigger `.onDisappear` on the presenter —
    /// it stays mounted underneath, so without an explicit hook here its
    /// audio just keeps running, unaware anything is now on top of it.
    var onPresentChange: ((Bool) -> Void)? = nil
    @State private var wasShowingAny = false
    var alignment: Alignment = .topTrailing
    var extraItems: [BurgerMenuItem] = []

    private func notifyIfChanged() {
        let isShowingAny = showChats || showSongs || showProfile || showSettings || showFriends || showNotifications
        guard isShowingAny != wasShowingAny else { return }
        wasShowingAny = isShowingAny
        onPresentChange?(isShowingAny)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: showChats) { _, _ in notifyIfChanged() }
            .onChange(of: showSongs) { _, _ in notifyIfChanged() }
            .onChange(of: showProfile) { _, _ in notifyIfChanged() }
            .onChange(of: showSettings) { _, _ in notifyIfChanged() }
            .onChange(of: showFriends) { _, _ in notifyIfChanged() }
            .onChange(of: showNotifications) { _, _ in notifyIfChanged() }
            .overlay(alignment: alignment) {
                Button { showMenu = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(16)
                }
            }
            .sheet(isPresented: $showMenu) {
                BurgerMenuSheet(
                    extraItems: extraItems,
                    onChats: {
                        showMenu = false
                        showChats = true
                    },
                    onSongs: {
                        showMenu = false
                        showSongs = true
                    },
                    onProfile: {
                        showMenu = false
                        showProfile = true
                    },
                    onSettings: {
                        showMenu = false
                        showSettings = true
                    },
                    onFriends: {
                        showMenu = false
                        showFriends = true
                    },
                    onNotifications: {
                        showMenu = false
                        showNotifications = true
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsHubView()
                    .environment(authState)
            }
            .fullScreenCover(isPresented: $showChats) {
                if authState.isSignedIn {
                    SessionListView()
                        .environment(authState)
                } else {
                    SignInView()
                        .environment(authState)
                }
            }
            .fullScreenCover(isPresented: $showSongs) {
                if authState.isSignedIn {
                    SongListView()
                        .environment(authState)
                } else {
                    SignInView()
                        .environment(authState)
                }
            }
            .fullScreenCover(isPresented: $showProfile) {
                NavigationStack {
                    ProfileView(onBack: { showProfile = false })
                        .environment(authState)
                }
            }
            .fullScreenCover(isPresented: $showFriends) {
                if authState.isSignedIn {
                    FriendsView()
                        .environment(authState)
                } else {
                    SignInView()
                        .environment(authState)
                }
            }
            .fullScreenCover(isPresented: $showNotifications) {
                if authState.isSignedIn {
                    NotificationsView()
                        .environment(authState)
                } else {
                    SignInView()
                        .environment(authState)
                }
            }
    }
}

private struct BurgerMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    let extraItems: [BurgerMenuItem]
    let onChats: () -> Void
    let onSongs: () -> Void
    let onProfile: () -> Void
    let onSettings: () -> Void
    let onFriends: () -> Void
    let onNotifications: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundTop.ignoresSafeArea()
                VStack(spacing: 10) {
                    ForEach(extraItems) { item in
                        row(label: L(item.label), systemImage: item.systemImage) {
                            dismiss()
                            item.action()
                        }
                    }
                    row(label: L("Your Chats"), systemImage: "bubble.left.and.bubble.right.fill", action: onChats)
                    row(label: L("My Songs"), systemImage: "music.note.list", action: onSongs)
                    row(label: L("Friends"), systemImage: "person.2.fill", action: onFriends)
                    row(label: L("Notifications"), systemImage: "bell.fill", action: onNotifications)
                    row(label: L("Settings"), systemImage: "gearshape.fill", action: onSettings)
                    row(label: L("Profile"), systemImage: "person.circle.fill", action: onProfile)
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(L("Menu"))
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

    private func row(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow.opacity(0.85))
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Adds a top-right burger button that opens Your Chats / Profile, plus
    /// any screen-specific rows passed via `extraItems`. Pass `onPresentChange`
    /// if the host has its own ambient audio/animation that needs to pause
    /// while any of this menu's destinations are covering the screen.
    func withBurgerMenu(
        alignment: Alignment = .topTrailing,
        extraItems: [BurgerMenuItem] = [],
        onPresentChange: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(BurgerMenuOverlay(onPresentChange: onPresentChange, alignment: alignment, extraItems: extraItems))
    }
}
