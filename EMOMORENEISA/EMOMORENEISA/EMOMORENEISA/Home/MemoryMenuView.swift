import SwiftUI
import SwiftData

/// Memory sub-menu: Your Words Calendar (the existing Memorize hub) and
/// Remember with Music (new, placeholder for now).
struct MemoryMenuView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showCalendar = false
    @State private var showMusic = false
    @State private var calendarCardPressed = false
    @State private var musicCardPressed = false
    @State private var appear = false

    var body: some View {
        ZStack {
            GameBackground()
            DreamParticlesView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: HomeLayout.cardSpacing) {
                    calendarCard(illustrationH: HomeLayout.illustrationHeight)
                    musicCard(illustrationH: HomeLayout.illustrationHeight)
                }
                .padding(.horizontal, HomeLayout.hPadding)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                BackButton { dismiss() }
                    .padding(.leading, HomeLayout.hPadding)
                    .padding(.top, 56)
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 40)
        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.08), value: appear)
        .onAppear { appear = true }
        .fullScreenCover(isPresented: $showCalendar) {
            MemorizeContainerView()
                .environment(authState)
        }
        .fullScreenCover(isPresented: $showMusic) {
            ComingSoonView(
                title: L("Remember with Music"),
                message: L("learn vocabulary through songs"),
                systemImage: "music.note"
            )
        }
    }

    private func calendarCard(illustrationH: CGFloat) -> some View {
        Button(action: { showCalendar = true }) {
            HomeModeCard(
                title: L("Your Words Calendar"),
                subtitle: L("everyday queue for new words"),
                badge: memorizeDueCount,
                pressed: calendarCardPressed
            ) {
                Image("progress_screen")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in calendarCardPressed = true }
                .onEnded { _ in calendarCardPressed = false }
        )
    }

    private func musicCard(illustrationH: CGFloat) -> some View {
        Button(action: { showMusic = true }) {
            HomeModeCard(
                title: L("Remember with Music"),
                subtitle: L("learn vocabulary through songs"),
                pressed: musicCardPressed
            ) {
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH * 0.6)
                    .foregroundColor(.yellow.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in musicCardPressed = true }
                .onEnded { _ in musicCardPressed = false }
        )
    }

    private var memorizeDueCount: Int {
        MemoryCardService(context: modelContext).dueCount()
    }
}
