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
    @State private var showProfile = false
    var alignment: Alignment = .topTrailing
    var extraItems: [BurgerMenuItem] = []

    func body(content: Content) -> some View {
        content
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
                    onProfile: {
                        showMenu = false
                        showProfile = true
                    }
                )
                .presentationDetents([.medium])
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
            .fullScreenCover(isPresented: $showProfile) {
                NavigationStack {
                    ProfileView(onBack: { showProfile = false })
                        .environment(authState)
                }
            }
    }
}

private struct BurgerMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    let extraItems: [BurgerMenuItem]
    let onChats: () -> Void
    let onProfile: () -> Void

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
    /// any screen-specific rows passed via `extraItems`.
    func withBurgerMenu(alignment: Alignment = .topTrailing, extraItems: [BurgerMenuItem] = []) -> some View {
        modifier(BurgerMenuOverlay(alignment: alignment, extraItems: extraItems))
    }
}
