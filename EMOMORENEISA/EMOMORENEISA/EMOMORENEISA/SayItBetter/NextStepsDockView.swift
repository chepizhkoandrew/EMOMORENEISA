import SwiftUI

/// The single persistent "Next steps" panel described in the lesson-flow
/// design: swappable content, never a bubble in the message list, and
/// mutually exclusive with `suggestionsButton` in the same dock slot — at
/// most one of the two is ever visible. Renders in the exact spot
/// `suggestionsButton` occupies in `ChatView`'s body VStack.
struct NextStepsDockView: View {
    let primaryLabel: String
    let secondaryLabel: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    /// After-practice only: a lower-emphasis third action ("Listen to this
    /// chapter again") — not a competing decision like the two buttons
    /// above, so it renders as a quiet text link underneath rather than a
    /// third capsule crowding the row.
    var tertiaryLabel: String? = nil
    var onTertiary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text(L("Next steps"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onSecondary) {
                    Text(secondaryLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.cardBackground)
                        .overlay(Capsule().stroke(AppColors.cardBorder, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let tertiaryLabel, let onTertiary {
                Button(action: onTertiary) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tertiaryLabel)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }
}
