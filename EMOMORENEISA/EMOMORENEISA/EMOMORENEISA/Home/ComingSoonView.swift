import SwiftUI

/// Generic placeholder screen for menu items whose real content doesn't
/// exist yet (Role Play, Remember with Music, Explain Rules, Ask in a Free
/// Forum). `title`/`message` are passed in already localized by the caller,
/// matching how every other screen in the app localizes at the call site.
struct ComingSoonView: View {
    let title: String
    let message: String
    let systemImage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GameBackground()

            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundColor(.yellow.opacity(0.55))

                Text(L("Coming soon"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow.opacity(0.75))
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
