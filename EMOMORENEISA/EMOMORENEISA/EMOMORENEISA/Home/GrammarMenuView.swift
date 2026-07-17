import SwiftUI

/// Grammar sub-menu: Explain Rules (placeholder), Verbs & Times (the
/// existing slot-machine game, relocated here), Ask in a Free Forum
/// (placeholder).
struct GrammarMenuView: View {
    let onVerbGame: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showExplainRules = false
    @State private var showFreeForum = false
    @State private var explainCardPressed = false
    @State private var verbsCardPressed = false
    @State private var forumCardPressed = false
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
                    explainRulesCard(illustrationH: HomeLayout.illustrationHeight)
                    verbsTimesCard(illustrationH: HomeLayout.illustrationHeight)
                    freeForumCard(illustrationH: HomeLayout.illustrationHeight)
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
        .fullScreenCover(isPresented: $showExplainRules) {
            ComingSoonView(
                title: L("Explain Rules"),
                message: L("browse grammar topics & lessons"),
                systemImage: "text.book.closed.fill"
            )
        }
        .fullScreenCover(isPresented: $showFreeForum) {
            ComingSoonView(
                title: L("Ask in a Free Forum"),
                message: L("ask anything, attach a photo"),
                systemImage: "questionmark.bubble.fill"
            )
        }
    }

    private func explainRulesCard(illustrationH: CGFloat) -> some View {
        Button(action: { showExplainRules = true }) {
            HomeModeCard(
                title: L("Explain Rules"),
                subtitle: L("browse grammar topics & lessons"),
                pressed: explainCardPressed
            ) {
                Image(systemName: "text.book.closed.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH * 0.6)
                    .foregroundColor(.yellow.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in explainCardPressed = true }
                .onEnded { _ in explainCardPressed = false }
        )
    }

    private func verbsTimesCard(illustrationH: CGFloat) -> some View {
        Button(action: onVerbGame) {
            HomeModeCard(
                title: L("Verbs & times"),
                subtitle: L("game to learn verbs & tenses fast"),
                pressed: verbsCardPressed
            ) {
                Image("verb_game")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in verbsCardPressed = true }
                .onEnded { _ in verbsCardPressed = false }
        )
    }

    private func freeForumCard(illustrationH: CGFloat) -> some View {
        Button(action: { showFreeForum = true }) {
            HomeModeCard(
                title: L("Ask in a Free Forum"),
                subtitle: L("ask anything, attach a photo"),
                pressed: forumCardPressed
            ) {
                Image(systemName: "questionmark.bubble.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH * 0.6)
                    .foregroundColor(.yellow.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in forumCardPressed = true }
                .onEnded { _ in forumCardPressed = false }
        )
    }
}
