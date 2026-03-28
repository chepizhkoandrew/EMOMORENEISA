import SwiftUI

struct SpinningWheelView: View {
    let finalVerb: String
    let translation: String?
    let isJoker: Bool
    let delay: Double
    let skipRequested: Bool
    let onStopped: (() -> Void)?

    private static let frameCount = 5

    @State private var frameIndex: Int = 0
    @State private var showVerb = false
    @State private var showSparkles = false
    @State private var verbScale: CGFloat = 0
    @State private var verbOpacity: Double = 0
    @State private var verbRotationX: Double = -70
    @State private var visibleLetters: Int = 0
    @State private var spinDone = false

    var body: some View {
        ZStack {
            wheelImage

            if showSparkles {
                ForEach(0..<10, id: \.self) { i in
                    SparkleParticle(
                        color: isJoker ? .orange : .yellow,
                        angle: Double(i) * 36.0
                    )
                }
            }

            if showVerb {
                verbOverlay
            }
        }
        .onAppear { startSpin() }
        .onChange(of: skipRequested) { _, requested in
            if requested && !spinDone { revealVerb() }
        }
    }

    private var wheelImage: some View {
        Group {
            if let img = UIImage(named: "wheel_\(frameIndex + 1)") {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.yellow.opacity(0.4), lineWidth: 2)
                    )
                    .aspectRatio(0.55, contentMode: .fit)
            }
        }
    }

    private var verbOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.82))
                .frame(height: translation != nil ? 80 : 60)
                .padding(.horizontal, 8)
                .opacity(verbOpacity)

            VStack(spacing: 2) {
                Text(String(finalVerb.prefix(visibleLetters)))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(isJoker ? .orange : .yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 12)
                    .shadow(color: isJoker ? .orange.opacity(0.9) : .yellow.opacity(0.9), radius: 8)
                    .shadow(color: .black, radius: 2)

                if let t = translation {
                    Text(t)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                }

                if isJoker {
                    Text("JOKER")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
            .scaleEffect(verbScale)
            .opacity(verbOpacity)
            .rotation3DEffect(.degrees(verbRotationX), axis: (x: 1, y: 0, z: 0))
        }
    }

    private func startSpin() {
        let totalTicks = 32 + Int.random(in: 0...8)
        var tick = 0

        func scheduleNext() {
            guard !spinDone else { return }
            let progress = Double(tick) / Double(totalTicks)
            let interval: Double
            if progress < 0.5 {
                interval = 0.055
            } else {
                let slow = (progress - 0.5) / 0.5
                interval = 0.055 + slow * 0.35
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                guard !spinDone else { return }
                frameIndex = (frameIndex + 1) % Self.frameCount
                tick += 1
                if tick < totalTicks {
                    scheduleNext()
                } else {
                    revealVerb()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !spinDone else { return }
            scheduleNext()
        }
    }

    private func revealVerb() {
        guard !spinDone else { return }
        spinDone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showVerb = true
            showSparkles = true
            visibleLetters = 0

            withAnimation(.spring(response: 0.45, dampingFraction: 0.58)) {
                verbScale = 1.0
                verbOpacity = 1.0
                verbRotationX = 0
            }

            let letters = Array(finalVerb)
            for (i, _) in letters.enumerated() {
                let delay = 0.1 + Double(i) * 0.07
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    visibleLetters = i + 1
                }
            }

            let totalLetterDelay = 0.1 + Double(letters.count) * 0.07 + 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.35, totalLetterDelay)) {
                onStopped?()
            }
        }
    }
}

struct SparkleParticle: View {
    let color: Color
    let angle: Double

    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    private let distance = CGFloat.random(in: 40...72)
    private let size = CGFloat.random(in: 5...10)

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(
                x: cos(angle * .pi / 180) * offset,
                y: sin(angle * .pi / 180) * offset
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    offset = distance
                }
                withAnimation(.easeIn(duration: 0.35).delay(0.25)) {
                    opacity = 0
                }
            }
    }
}
