import SwiftUI

// MARK: - Chat / UI Colors

enum AppColors {
    // Same gradient stops as GameColors — one canonical background color for
    // every screen; only the amount of decoration layered on top differs.
    static let backgroundTop = GameColors.backgroundTop
    static let backgroundBottom = GameColors.backgroundBottom
    static let accent = Color.yellow
    static let cardBackground = Color.white.opacity(0.07)
    static let cardBorder = Color.white.opacity(0.10)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary = Color.white.opacity(0.38)
    static let inputBackground = Color.white.opacity(0.08)
    static let inputBorder = Color.white.opacity(0.13)
    static let toolbarBackground = GameColors.backgroundTop
}

// MARK: - Game Colors

enum GameColors {
    static let backgroundTop    = Color(red: 0.07, green: 0.06, blue: 0.18)
    static let backgroundBottom = Color(red: 0.03, green: 0.03, blue: 0.12)

    static let gold   = Color.yellow
    static let coral  = Color.orange
    static let verde  = Color(red: 0.18, green: 0.82, blue: 0.44)
    static let rojo   = Color(red: 0.95, green: 0.22, blue: 0.22)

    static let cellIdle    = Color.white.opacity(0.09)
    static let cellBorder  = Color.white.opacity(0.18)

    static let correctGradient = LinearGradient(
        colors: [Color(red: 0.18, green: 0.82, blue: 0.44).opacity(0.38), Color(red: 0.18, green: 0.82, blue: 0.44).opacity(0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let missedGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.22, blue: 0.22).opacity(0.38), Color(red: 0.95, green: 0.22, blue: 0.22).opacity(0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let activeGradient = LinearGradient(
        colors: [Color.yellow.opacity(0.22), Color.yellow.opacity(0.08)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let verbBadgeGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.85, blue: 0.15), Color(red: 0.92, green: 0.66, blue: 0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let jokerBadgeGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.55, blue: 0.18), Color(red: 0.88, green: 0.36, blue: 0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let verbGameCardTop    = Color(red: 0.95, green: 0.76, blue: 0.10)
    static let verbGameCardBottom = Color(red: 0.75, green: 0.50, blue: 0.02)
    static let chatCardTop        = Color(red: 0.10, green: 0.56, blue: 0.96)
    static let chatCardBottom     = Color(red: 0.04, green: 0.32, blue: 0.78)
}

// MARK: - Chat Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.80, blue: 0.10).opacity(0.07))
                        .frame(width: w * 0.85)
                        .blur(radius: 90)
                        .offset(x: -w * 0.28, y: -h * 0.18)

                    Circle()
                        .fill(Color(red: 0.45, green: 0.18, blue: 0.85).opacity(0.06))
                        .frame(width: w * 0.65)
                        .blur(radius: 80)
                        .offset(x: w * 0.32, y: h * 0.38)

                    Circle()
                        .fill(Color(red: 0.90, green: 0.40, blue: 0.10).opacity(0.04))
                        .frame(width: w * 0.55)
                        .blur(radius: 70)
                        .offset(x: w * 0.05, y: h * 0.72)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Game Background

struct GameBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GameColors.backgroundTop, GameColors.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.08))
                        .frame(width: w * 0.70)
                        .blur(radius: 80)
                        .offset(x: w * 0.15, y: -h * 0.25)

                    Circle()
                        .fill(Color(red: 0.35, green: 0.10, blue: 0.95).opacity(0.09))
                        .frame(width: w * 0.55)
                        .blur(radius: 70)
                        .offset(x: -w * 0.20, y: h * 0.45)

                    Circle()
                        .fill(Color.cyan.opacity(0.05))
                        .frame(width: w * 0.45)
                        .blur(radius: 60)
                        .offset(x: w * 0.35, y: h * 0.70)
                }
            }
            .ignoresSafeArea()

            StarFieldView()
                .ignoresSafeArea()
        }
    }
}

// MARK: - Star Field (subtle dot pattern for game screens)

struct StarFieldView: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
    }

    private let stars: [Star] = (0..<60).map { _ in
        Star(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 1...2.5),
            opacity: Double.random(in: 0.06...0.25)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(stars.indices, id: \.self) { i in
                let s = stars[i]
                Circle()
                    .fill(Color.white.opacity(s.opacity))
                    .frame(width: s.size, height: s.size)
                    .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
            }
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var running = false

    private let colors: [Color] = [.yellow, .green, .cyan, .orange, .pink, .white, .mint]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    for particle in particles {
                        let elapsed = now - particle.startTime
                        guard elapsed >= 0 else { continue }
                        let t = min(elapsed / particle.lifetime, 1.0)
                        if t >= 1 { continue }

                        let x = particle.startX + particle.vx * elapsed
                        let y = particle.startY + particle.vy * elapsed + 0.5 * 420 * elapsed * elapsed
                        let alpha = t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3
                        let rotation = Angle.degrees(particle.rotationSpeed * elapsed)

                        context.opacity = alpha
                        context.translateBy(x: x, y: y)
                        context.rotate(by: rotation)
                        let rect = CGRect(x: -particle.size / 2, y: -particle.size / 2,
                                          width: particle.size, height: particle.size * 0.55)
                        let path = Path(rect)
                        context.fill(path, with: .color(particle.color))
                        context.rotate(by: .degrees(-rotation.degrees))
                        context.translateBy(x: -x, y: -y)
                    }
                }
                .onAppear {
                    spawnParticles(in: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func spawnParticles(in size: CGSize) {
        let now = Date.timeIntervalSinceReferenceDate
        particles = (0..<120).map { i in
            ConfettiParticle(
                startX: CGFloat.random(in: 0...size.width),
                startY: CGFloat.random(in: -80...(-10)),
                vx: CGFloat.random(in: -60...60),
                vy: CGFloat.random(in: 60...180),
                color: colors.randomElement()!,
                size: CGFloat.random(in: 7...16),
                rotationSpeed: Double.random(in: -360...360),
                lifetime: Double.random(in: 2.0...3.5),
                startTime: now + Double(i) * 0.022
            )
        }
    }
}

private struct ConfettiParticle {
    let startX: CGFloat
    let startY: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let color: Color
    let size: CGFloat
    let rotationSpeed: Double
    let lifetime: Double
    let startTime: TimeInterval
}

// MARK: - Back Button (shared across all screens)

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home Layout (shared sizing for Home + New Session mode pickers)

enum HomeLayout {
    static let cardHeight: CGFloat = 96
    static let illustrationHeight: CGFloat = 78
    static let cardSpacing: CGFloat = 14
    static let hPadding: CGFloat = 20

    static func dogHeight(_ screenHeight: CGFloat) -> CGFloat {
        min(screenHeight * 0.40, 320)
    }
}

// MARK: - Home Mode Card (single cohesive dark style across all home screens)

struct HomeModeCard<Illustration: View>: View {
    let title: String
    let subtitle: String
    var badge: Int = 0
    var pressed: Bool = false
    @ViewBuilder var illustration: () -> Illustration

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.18, blue: 0.34),
                            Color(red: 0.10, green: 0.11, blue: 0.22)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.yellow)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                illustration()
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
        }
        .frame(height: HomeLayout.cardHeight)
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
