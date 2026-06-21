import SwiftUI

/// A single word rendered as its current material token (Agua → Wood → Stone →
/// Gold → Microchip). Uses the named material art slot with an SF-Symbol
/// fallback so it renders before art lands. Spec §3.1 / §3.4.
struct MaterialTokenView: View {
    let stage: MemoryStage
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(stage.tokenColor.opacity(0.20))
            Circle()
                .stroke(stage.tokenColor.opacity(0.55), lineWidth: 1.5)

            if stage.hasArt {
                Image(stage.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Image(systemName: stage.placeholderSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(stage.tokenColor)
            }
        }
        .frame(width: size, height: size)
    }
}

extension MemoryStage {
    /// True once the named material-token art has been delivered.
    var hasArt: Bool { UIImage(named: assetName) != nil }
}
