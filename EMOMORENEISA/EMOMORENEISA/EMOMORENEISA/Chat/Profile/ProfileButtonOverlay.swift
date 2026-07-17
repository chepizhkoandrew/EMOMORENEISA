import SwiftUI

// Reusable "profile entry point" for feature screens outside the main menu
// (Explore, Memorize, Verbs & Times). Each usage owns its OWN `showProfile`
// state, so presenting/dismissing it always returns to whichever screen
// hosted the modifier — never to the main menu — mirroring the fullScreenCover
// + onBack pattern already used by ModeSelectorView/SessionListView.
struct ProfileButtonOverlay: ViewModifier {
    @Environment(AuthState.self) private var authState
    @State private var showProfile = false
    var alignment: Alignment = .topTrailing

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                Button { showProfile = true } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 28, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(16)
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

extension View {
    /// Adds the same top-right profile button used on the main menu, scoped
    /// to this screen — back navigation from Profile returns here, not to
    /// the main menu. Pass a different `alignment` when the default corner
    /// is already occupied by another control (e.g. a settings gear).
    func withProfileButton(alignment: Alignment = .topTrailing) -> some View {
        modifier(ProfileButtonOverlay(alignment: alignment))
    }
}
