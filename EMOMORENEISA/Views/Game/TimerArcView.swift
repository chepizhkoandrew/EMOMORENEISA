import SwiftUI

struct TimerArcView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    timerColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: progress)
        }
    }

    private var timerColor: Color {
        if progress > 0.5 { return .green }
        if progress > 0.25 { return .yellow }
        return .red
    }
}
