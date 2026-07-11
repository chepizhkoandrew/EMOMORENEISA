import SwiftUI

/// The Loro Memorize 3-tab shell (spec §11.1): Hub · Vocabulary · Progress, with
/// a Settings gear. Presented from Home in place of the bare Hub.
struct MemorizeContainerView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .hub
    @State private var showSettings = false
    @State private var showProfile = false

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
            trailingButtons
        }
        .sheet(isPresented: $showSettings) {
            MemorizeSettingsView()
        }
        .fullScreenCover(isPresented: $showProfile) {
            NavigationStack {
                ProfileView(onBack: { showProfile = false })
                    .environment(authState)
            }
        }
    }

    private var backButton: some View {
        HStack {
            BackButton { dismiss() }
                .padding(.leading, 16)
                .padding(.top, 54)
            Spacer()
        }
    }

    // Profile sits in the same corner the main menu uses; settings gear
    // moves one slot inward so the two never overlap.
    private var trailingButtons: some View {
        HStack(spacing: 10) {
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.yellow)
                    .padding(10)
                    .background(Color.black.opacity(0.25))
                    .clipShape(Circle())
            }
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 54)
    }
}
