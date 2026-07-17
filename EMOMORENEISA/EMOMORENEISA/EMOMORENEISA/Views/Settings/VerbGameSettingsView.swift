import SwiftUI

/// "Verbs & times" game settings — tense, per-word timer, and answer hint for
/// the verb-conjugation game. Persisted via `@AppStorage` (shared with the game
/// itself). Restyled to the app's standard `Form` look so it matches the rest
/// of Settings (it previously used a bespoke monospaced card layout).
///
/// A *pushable* page for `SettingsHubView`; the standalone in-game sheet
/// (`SettingsSheetView`) wraps this same view in its own NavigationStack.
struct VerbGameSettingsView: View {
    @AppStorage("timerSeconds") private var timerSeconds: Double = 4.0
    @AppStorage("selectedTenseName") private var selectedTenseName: String = Tense.present.rawValue
    @AppStorage("showAnswerHint") private var showAnswerHint: Bool = false

    private var tenseBinding: Binding<Tense> {
        Binding(
            get: { Tense(rawValue: selectedTenseName) ?? .present },
            set: { selectedTenseName = $0.rawValue }
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section(L("Tense")) {
                    Picker(L("Tense"), selection: tenseBinding) {
                        ForEach(Tense.allCases) { tense in
                            Text(tense.displayLabel).tag(tense)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(L("Timer")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("Timer per word"))
                            Spacer()
                            Text(L("%.1fs", timerSeconds))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.yellow)
                        }
                        Slider(value: $timerSeconds, in: 1.0...8.0, step: 0.5)
                            .tint(.yellow)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(L("Show answer hint"), isOn: $showAnswerHint)
                } footer: {
                    Text(L("Reveal the correct conjugation under each cell as the timer runs."))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .tint(.yellow)
        .navigationTitle(L("Verbs & times"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
