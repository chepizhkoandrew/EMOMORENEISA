import SwiftUI

/// "User settings" — app-wide preferences that used to live in the Profile
/// screen: interface language, how the tutor addresses the user (pronoun), and
/// automatic voice replies. This is now the single home for these toggles; the
/// Profile screen keeps identity, treats, level, stats, and account actions.
///
/// A *pushable* page for `SettingsHubView`'s NavigationStack (Settings → User
/// settings). Future app-level preferences belong here.
struct AppSettingsView: View {
    @Environment(AuthState.self) private var authState
    @State private var loc = LocalizationManager.shared
    @State private var editingPronoun: UserPronoun = .they
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true

    private var profile: ESPProfile? { authState.profile }

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section(L("Language")) {
                    Picker(L("App Language"), selection: Binding(
                        get: { loc.language },
                        set: { loc.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flag)  \(lang.nativeName)").tag(lang)
                        }
                    }
                }

                Section {
                    Picker(L("Pronoun"), selection: $editingPronoun) {
                        ForEach(UserPronoun.allCases) { pronoun in
                            Text("\(pronoun.ukLabel) · \(pronoun.displayLabel)").tag(pronoun)
                        }
                    }
                    .onChange(of: editingPronoun) { _, _ in savePronoun() }
                } header: {
                    Text(L("Pronoun"))
                } footer: {
                    Text(L("This shapes how your tutor addresses you — especially gendered endings in Ukrainian."))
                }

                Section {
                    Toggle(L("Automatic voice replies"), isOn: $autoVoiceEnabled)
                } header: {
                    Text(L("Voice"))
                } footer: {
                    Text(L("Turn off to save treats — tap a message to hear it on demand."))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .tint(.yellow)
        .navigationTitle(L("User settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            editingPronoun = profile?.userPronoun.flatMap(UserPronoun.init(rawValue:)) ?? .they
        }
    }

    private func savePronoun() {
        guard var p = profile else { return }
        p.userPronoun = editingPronoun.rawValue
        p.updatedAt = Date()
        // Update the in-memory profile immediately so the change takes effect on
        // the very next chat message (PromptBuilder reads authState.profile
        // fresh per message), then persist to Supabase.
        authState.profile = p
        Task { await SupabaseSyncService.shared.updateProfile(p) }
    }
}
