import SwiftUI

/// The five-stop forgetting-horizon strip (1h · 3d · 1mo · 1yr · 5yr) with the
/// word's current stage lit. Spec §3.4. Doubles as the per-card 13→5 progress
/// indicator (the lit position is derived from `MemoryStage`, never from raw
/// `exposureCount`).
struct HorizonStripView: View {
    let stage: MemoryStage
    var compact: Bool = false

    private let stages = MemoryStage.allCases

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(Array(stages.enumerated()), id: \.offset) { idx, s in
                let isCurrent = s == stage
                let isReached = idx <= stage.progressIndex

                VStack(spacing: 4) {
                    Circle()
                        .fill(isReached ? s.tokenColor : Color.white.opacity(0.12))
                        .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isCurrent ? 0.8 : 0), lineWidth: 1.5)
                        )

                    if !compact {
                        Text(s.stripLabel)
                            .font(.system(size: 10, weight: isCurrent ? .bold : .regular, design: .rounded))
                            .foregroundColor(isCurrent ? AppColors.textPrimary : AppColors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                if idx < stages.count - 1 {
                    Rectangle()
                        .fill(idx < stage.progressIndex ? stage.tokenColor.opacity(0.5) : Color.white.opacity(0.10))
                        .frame(height: 2)
                }
            }
        }
    }
}

/// A thin per-card 0–13 progress bar shown as the 5 material milestones. Spec §3.3.
struct CardProgressBar: View {
    let exposureCount: Int

    var body: some View {
        let clamped = min(13, max(0, exposureCount))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(MemoryStage.stage(forExposureCount: exposureCount).tokenColor)
                    .frame(width: geo.size.width * CGFloat(clamped) / 13.0)
            }
        }
        .frame(height: 5)
    }
}
