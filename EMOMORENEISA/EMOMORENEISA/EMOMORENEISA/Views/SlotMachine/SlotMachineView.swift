import SwiftUI

struct SlotMachineView: View {
    @EnvironmentObject var engine: GameEngine
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var stoppedCount = 0
    @State private var skipSpinRequested = false

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var isSpinning: Bool { engine.phase == .spinning }

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
                            delay: Double(index) * 0.5,
                            skipRequested: skipSpinRequested
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

                Color.clear.frame(height: isLandscape ? 72 : 160)
            }

            VStack {
                Spacer()

                if isSpinning {
                    Text("tap to reveal")
                        .font(.system(size: isLandscape ? 13 : 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                        .tracking(1)
                        .transition(.opacity)
                        .padding(.bottom, isLandscape ? 16 : 36)
                } else if engine.phase == .readyToStart {
                    if isLandscape {
                        Text("tap to practice")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .tracking(1)
                            .transition(.opacity)
                            .onTapGesture { engine.beginCountdown() }
                            .padding(.bottom, 16)
                    } else {
                        PlayToLearnButton(compact: false) {
                            engine.beginCountdown()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .padding(.bottom, 36)
                    }
                } else if case .countdown(let n) = engine.phase {
                    Text("\(n)")
                        .font(.system(size: isLandscape ? 60 : 100, weight: .black, design: .monospaced))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.7), radius: 16)
                        .transition(.scale.combined(with: .opacity))
                        .id(n)
                        .padding(.bottom, isLandscape ? 10 : 36)
                } else {
                    Color.clear.frame(height: isLandscape ? 72 : 160)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: engine.phase == .readyToStart)
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    private func handleTap() {
        switch engine.phase {
        case .spinning:
            skipSpinRequested = true
        case .readyToStart:
            engine.beginCountdown()
        default:
            break
        }
    }
}

struct PlayToLearnButton: View {
    var compact: Bool = false
    let action: () -> Void
    @State private var isPressed: Bool = false

    private var size: CGFloat { compact ? 80 : 160 }
    private var circleSize: CGFloat { compact ? 65 : 130 }
    private var textRadius: CGFloat { compact ? 24 : 49 }
    private var textFontSize: CGFloat { compact ? 5 : 10 }
    private var buttonSize: CGFloat { compact ? 37 : 74 }
    private var shadowSize: CGFloat { compact ? 36 : 72 }
    private var cornerRadius: CGFloat { compact ? 7 : 13 }
    private var screwOffset: CGFloat { compact ? 30 : 60 }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.76, blue: 0.05), Color(red: 0.72, green: 0.56, blue: 0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color(red: 0.55, green: 0.42, blue: 0.0).opacity(0.7), lineWidth: 1.5)
                    )

                ForEach([(-screwOffset, -screwOffset), (screwOffset, -screwOffset), (-screwOffset, screwOffset), (screwOffset, screwOffset)].map { CGPoint(x: $0.0, y: $0.1) }, id: \.x) { pt in
                    ScrewView()
                        .offset(x: pt.x, y: pt.y)
                }

                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.84, blue: 0.15))
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: Color(red: 0.5, green: 0.38, blue: 0.0).opacity(0.5), radius: 4, y: 2)

                    CircularTextView(text: "PLAY  TO  LEARN  ★  ", radius: textRadius, fontSize: textFontSize)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    ZStack {
                        Circle()
                            .fill(Color(red: 0.45, green: 0.0, blue: 0.0))
                            .frame(width: shadowSize, height: shadowSize)
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
                                    endRadius: compact ? 20 : 40
                                )
                            )
                            .frame(width: buttonSize, height: isPressed ? buttonSize * 0.92 : buttonSize)
                            .offset(y: isPressed ? 3 : 0)

                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: buttonSize * 0.54, height: buttonSize * 0.3)
                            .offset(x: compact ? -3 : -6, y: isPressed ? (compact ? -6 : -12) : (compact ? -9 : -17))
                            .blur(radius: compact ? 2 : 3)
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
