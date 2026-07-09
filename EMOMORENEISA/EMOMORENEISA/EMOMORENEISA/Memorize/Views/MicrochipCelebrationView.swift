import SwiftUI

/// The signature moment (spec §3.2): a word crosses `exposureCount >= 13` and is
/// etched in a microchip — El Loro won't forget it for years. Reuses the shipped
/// `ConfettiView` for milestone counts only and honors Reduce Motion with a
/// static fallback (spec §19).
struct MicrochipCelebrationView: View {
    let card: MemoryCard
    let knownCount: Int
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    /// Confetti only at milestone totals — never blocks a passive session.
    private var isMilestone: Bool {
        [10, 25, 50, 100, 250, 500].contains(knownCount)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            if isMilestone {
                ConfettiView()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 18) {
                MaterialTokenView(stage: .microchip, size: 110)
                    .scaleEffect(reduceMotion ? 1 : (shimmer ? 1.06 : 0.94))
                    .shadow(color: MemoryStage.microchip.tokenColor.opacity(0.6), radius: 24)

                Text(card.content)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("¡Eso es! " + L("Loro won't forget this for years. That's word #%d.", knownCount))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Text(LPlural(knownCount,
                             en: "Seagull Steven knows %d word",
                             "Seagull Steven knows %d words",
                             uk: "Чайка Стівен знає %d слово",
                             "Чайка Стівен знає %d слова",
                             "Чайка Стівен знає %d слів"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)

                Button(action: onDismiss) {
                    Text("¡Vamos!")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.30), lineWidth: 1.5))
            )
            .padding(.horizontal, 32)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }
}
