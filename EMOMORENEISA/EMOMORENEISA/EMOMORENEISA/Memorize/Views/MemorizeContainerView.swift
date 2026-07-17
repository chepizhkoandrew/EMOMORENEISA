import SwiftUI

/// The Loro Memorize shell (spec §11.1): Hub · Progress. Chats, Profile, and
/// Settings (Words queue / Verbs & times / User settings) all live in the shared
/// burger menu, top-right — the same menu used on Home — so this screen no longer
/// carries its own gear + profile buttons.
struct MemorizeContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .hub

    enum Tab: Hashable { case hub, progress }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $tab) {
                LoroMemorizeHubView(showsBackButton: false)
                    .tabItem { Label(L("Seagull"), systemImage: "bird.fill") }
                    .tag(Tab.hub)

                LoroStatsView()
                    .tabItem { Label(L("Progress"), systemImage: "chart.bar.fill") }
                    .tag(Tab.progress)
            }
            .tint(.yellow)

            backButton
        }
        .withBurgerMenu()
    }

    private var backButton: some View {
        HStack {
            BackButton { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 54)
            Spacer()
        }
    }
}
