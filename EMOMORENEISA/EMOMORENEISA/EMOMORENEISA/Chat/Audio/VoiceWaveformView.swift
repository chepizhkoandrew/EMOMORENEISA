import SwiftUI

struct VoiceWaveformView: View {
    let audioLevel: Float
    var color: Color = .yellow
    var barCount: Int = 7
    var maxHeight: CGFloat = 44
    var barWidth: CGFloat = 4
    var spacing: CGFloat = 5

    @State private var heights: [CGFloat] = []

    private let centerWeights: [Double] = [0.35, 0.55, 0.80, 1.00, 0.80, 0.55, 0.35]
    private let nineWeights:   [Double] = [0.25, 0.45, 0.70, 0.90, 1.00, 0.90, 0.70, 0.45, 0.25]
    private let fiveWeights:   [Double] = [0.45, 0.75, 1.00, 0.75, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: safeHeight(i))
                    .animation(.spring(response: 0.18, dampingFraction: 0.55), value: safeHeight(i))
            }
        }
        .onAppear { recalc() }
        .onChange(of: audioLevel) { _, _ in recalc() }
    }

    private func safeHeight(_ i: Int) -> CGFloat {
        guard i < heights.count else { return 4 }
        return heights[i]
    }

    private func recalc() {
        let level = Double(audioLevel)
        let weights = weights(for: barCount)
        let minH: CGFloat = 4
        var newHeights: [CGFloat] = []
        for w in weights {
            let noise = Double.random(in: 0.72...1.28)
            let h = CGFloat(level * maxHeight * w * noise)
            newHeights.append(max(minH, h))
        }
        heights = newHeights
    }

    private func weights(for count: Int) -> [Double] {
        switch count {
        case 5:  return fiveWeights
        case 9:  return nineWeights
        default: return centerWeights
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 24) {
            VoiceWaveformView(audioLevel: 0.0)
            VoiceWaveformView(audioLevel: 0.4)
            VoiceWaveformView(audioLevel: 0.9)
            VoiceWaveformView(audioLevel: 1.0, barCount: 9, maxHeight: 56)
        }
    }
    .frame(height: 300)
}
