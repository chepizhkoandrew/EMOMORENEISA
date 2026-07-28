import SwiftUI

/// Pre-game tense chooser for the verb-conjugation game, shown as a leaf from
/// `ModeSelectorView` right before the spin animation. Styled identically to
/// `SessionListView` ("My Chats") and `SayItBetterEntryView` — same
/// background, nav title, back button, and row card — since all three are
/// just list-of-list-like-things screens and shouldn't look like three
/// different apps.
struct TensePickerView: View {
    let onSelect: (Tense) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                tenseList
            }
            .navigationTitle(L("Choose a tense"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
    }

    private var tenseList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Tense.allCases) { tense in
                    Button {
                        onSelect(tense)
                    } label: {
                        TenseRowView(tense: tense)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

/// Mirrors `SessionRowView`/`LessonRowView` exactly — icon tile, title,
/// subtitle, chevron — so every list screen in the app reads as one
/// consistent pattern.
private struct TenseRowView: View {
    let tense: Tense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L(tense.displayLabel))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(example)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
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

    private var icon: String {
        switch tense {
        case .present:   return "circle.fill"
        case .preterite: return "arrow.left"
        case .imperfect: return "repeat"
        case .future:    return "arrow.right"
        }
    }

    private var example: String {
        switch tense {
        case .present:   return "yo hablo"
        case .preterite: return "yo hablé"
        case .imperfect: return "yo hablaba"
        case .future:    return "yo hablaré"
        }
    }
}
