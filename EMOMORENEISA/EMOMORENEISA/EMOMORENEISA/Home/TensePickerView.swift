import SwiftUI

/// Pre-game tense chooser for the verb-conjugation game, shown as a leaf from
/// `ModeSelectorView` right before the spin animation. Mirrors the dark
/// monospaced/yellow-accent styling of `SlotMachineView`/`VerbStatsView`
/// since it leads straight into that same screen sequence.
struct TensePickerView: View {
    let onSelect: (Tense) -> Void
    @Environment(\.dismiss) private var dismiss

    private let examples: [Tense: String] = [
        .present: "yo hablo",
        .preterite: "yo hablé",
        .imperfect: "yo hablaba",
        .future: "yo hablaré",
    ]

    var body: some View {
        ZStack {
            GameBackground()

            VStack(spacing: 22) {
                Text(L("Choose a tense"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 40)

                VStack(spacing: 14) {
                    ForEach(Tense.allCases) { tense in
                        Button {
                            onSelect(tense)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tense.displayLabel)
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    if let example = examples[tense] {
                                        Text(example)
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.yellow.opacity(0.7))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, HomeLayout.hPadding)

                Spacer()
            }

            VStack {
                HStack {
                    BackButton { dismiss() }
                        .padding(.leading, HomeLayout.hPadding)
                        .padding(.top, 56)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
