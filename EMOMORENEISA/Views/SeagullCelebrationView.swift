import SwiftUI

struct SeagullCelebrationView: View {
    var isAnimating: Bool
    var size: CGFloat = 200
    var repeatCount: Int = 2
    var onComplete: (() -> Void)? = nil

    private static let frames = [
        "seagull_celebrate_1",
        "seagull_celebrate_2",
        "seagull_celebrate_3",
        "seagull_celebrate_4",
        "seagull_celebrate_3",
        "seagull_celebrate_2",
    ]

    private static let yOffsets: [CGFloat] = [0, -12, -32, -52, -32, -12]

    @State private var frameIndex: Int = 0
    @State private var timer: Timer? = nil
    @State private var cycleCount: Int = 0

    var body: some View {
        Image(Self.frames[frameIndex])
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .offset(y: Self.yOffsets[frameIndex])
            .animation(.easeInOut(duration: 0.1), value: frameIndex)
            .onChange(of: isAnimating) { animating in
                if animating {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
            .onDisappear {
                stopAnimation()
            }
    }

    private func startAnimation() {
        frameIndex = 0
        cycleCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            let next = frameIndex + 1
            if next >= Self.frames.count {
                cycleCount += 1
                if cycleCount >= repeatCount {
                    stopAnimation()
                    onComplete?()
                    return
                }
                frameIndex = 0
            } else {
                frameIndex = next
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var animating = false
        var body: some View {
            VStack(spacing: 32) {
                SeagullCelebrationView(isAnimating: animating, size: 220, repeatCount: 3)

                Button(animating ? "Stop" : "Celebrate!") {
                    animating.toggle()
                }
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}
