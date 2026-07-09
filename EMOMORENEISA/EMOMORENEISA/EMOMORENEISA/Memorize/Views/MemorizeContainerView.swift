import SwiftUI

/// The Loro Memorize 3-tab shell (spec §11.1): Hub · Vocabulary · Progress, with
/// a Settings gear. Presented from Home in place of the bare Hub.
struct MemorizeContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .hub
    @State private var showSettings = false

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
            settingsGear
        }
        .sheet(isPresented: $showSettings) {
            MemorizeSettingsView()
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

    private var settingsGear: some View {
        HStack {
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
            .padding(.trailing, 16)
            .padding(.top, 54)
        }
    }
}
