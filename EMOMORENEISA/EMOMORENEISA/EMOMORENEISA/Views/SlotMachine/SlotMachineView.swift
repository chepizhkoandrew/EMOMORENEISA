import SwiftUI

struct SlotMachineView: View {
    @EnvironmentObject var engine: GameEngine

    @State private var stoppedCount = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        engine.newRound()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer(minLength: 0)

                HStack(spacing: -30) {
                    ForEach(Array(engine.selectedVerbs.enumerated()), id: \.offset) { index, verb in
                        SpinningWheelView(
                            finalVerb: verb.infinitive,
                            isJoker: verb.joker,
                            delay: Double(index) * 0.5
                        ) {
                            stoppedCount += 1
                            if stoppedCount == engine.selectedVerbs.count {
                                engine.onSpinComplete()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 0)

                Spacer(minLength: 0)

                Color.clear.frame(height: 160)
            }

            VStack {
                Spacer()

                if engine.phase == .readyToStart {
                    PlayToLearnButton {
                        engine.beginCountdown()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .padding(.bottom, 36)
                } else if case .countdown(let n) = engine.phase {
                    Text("\(n)")
                        .font(.system(size: 100, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.7), radius: 16)
                        .transition(.scale.combined(with: .opacity))
                        .id(n)
                        .padding(.bottom, 36)
                } else {
                    Color.clear.frame(height: 160)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: engine.phase == .readyToStart)
    }
}

struct PlayToLearnButton: View {
    let action: () -> Void
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.76, blue: 0.05), Color(red: 0.72, green: 0.56, blue: 0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color(red: 0.55, green: 0.42, blue: 0.0).opacity(0.7), lineWidth: 1.5)
                    )

                ForEach([(CGFloat(-60), CGFloat(-60)), (60, -60), (-60, CGFloat(60)), (CGFloat(60), CGFloat(60))], id: \.0) { (x, y) in
                    ScrewView()
                        .offset(x: x, y: y)
                }

                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.84, blue: 0.15))
                        .frame(width: 130, height: 130)
                        .shadow(color: Color(red: 0.5, green: 0.38, blue: 0.0).opacity(0.5), radius: 4, y: 2)

                    CircularTextView(text: "PLAY  TO  LEARN  ★  ", radius: 49, fontSize: 10)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    ZStack {
                        Circle()
                            .fill(Color(red: 0.45, green: 0.0, blue: 0.0))
                            .frame(width: 72, height: 72)
                            .offset(y: isPressed ? 3 : 6)
                            .blur(radius: 2)

                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.25, blue: 0.1),
                                        Color(red: 0.72, green: 0.0, blue: 0.0)
                                    ],
                                    center: .init(x: 0.38, y: 0.32),
                                    startRadius: 3,
                                    endRadius: 40
                                )
                            )
                            .frame(width: 74, height: isPressed ? 68 : 74)
                            .offset(y: isPressed ? 3 : 0)

                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 40, height: 22)
                            .offset(x: -6, y: isPressed ? -12 : -17)
                            .blur(radius: 3)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeIn(duration: 0.06)) { isPressed = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.3)) { isPressed = false } }
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.08), value: isPressed)
    }
}

struct ScrewView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.75), Color(white: 0.45)],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 1,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            Rectangle()
                .fill(Color(white: 0.28))
                .frame(width: 7, height: 1.8)
                .rotationEffect(.degrees(45))
            Rectangle()
                .fill(Color(white: 0.28))
                .frame(width: 7, height: 1.8)
                .rotationEffect(.degrees(-45))
        }
    }
}

struct CircularTextView: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                let angle = Double(index) / Double(text.count) * 360 - 90
                Text(String(char))
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .rotationEffect(.degrees(angle + 90))
                    .offset(
                        x: cos(angle * .pi / 180) * radius,
                        y: sin(angle * .pi / 180) * radius
                    )
            }
        }
    }
}
