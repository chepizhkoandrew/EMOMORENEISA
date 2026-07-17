import SwiftUI

/// The top level of the two-level Settings tree, reached from the burger menu.
/// It's a simple menu that pushes to each settings area:
///   Settings → Words queue         (Seagull's SRS scheduling & capacity)
///            → Verbs & times        (verb-conjugation game)
///            → User settings        (language, pronoun, voice replies)
///
/// Presented as a full-screen cover from `BurgerMenuOverlay`; the "Done" button
/// closes the whole cover, while the NavigationStack handles push/pop between
/// the hub and each detail page.
struct SettingsHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        NavigationLink {
                            WordsQueueSettingsView()
                        } label: {
                            row(title: L("Words queue"),
                                subtitle: L("Seagull Steven's memory schedule & capacity"),
                                systemImage: "brain.head.profile")
                        }

                        NavigationLink {
                            VerbGameSettingsView()
                        } label: {
                            row(title: L("Verbs & times"),
                                subtitle: L("Verb game tense, timer & hints"),
                                systemImage: "gamecontroller.fill")
                        }

                        NavigationLink {
                            AppSettingsView()
                        } label: {
                            row(title: L("User settings"),
                                subtitle: L("Language, pronoun & voice replies"),
                                systemImage: "person.crop.circle.badge.checkmark")
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                        .foregroundColor(.yellow)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.85))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
