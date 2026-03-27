import SwiftUI

struct SpinningWheelView: View {
    let items: [String]
    let finalItem: String
    let delay: Double
    let onStopped: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var stopped = false

    private let itemHeight: CGFloat = 64
    private let visibleItems = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                )

            GeometryReader { geo in
                let totalHeight = itemHeight * CGFloat(visibleItems)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(loopedItems, id: \.self) { item in
                            Text(item)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(item == finalItem && stopped ? .yellow : .white)
                                .frame(height: itemHeight)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .offset(y: offset)
                }
                .frame(height: totalHeight)
                .disabled(true)
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black, .black, .black, .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: itemHeight * CGFloat(visibleItems))

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow.opacity(0.3))
                .frame(height: itemHeight)
                .allowsHitTesting(false)
        }
        .frame(height: itemHeight * CGFloat(visibleItems))
        .onAppear {
            startSpin()
        }
    }

    private var loopedItems: [String] {
        var list: [String] = []
        for _ in 0..<20 { list.append(contentsOf: items) }
        list.append(finalItem)
        return list
    }

    private func startSpin() {
        let totalScroll = itemHeight * CGFloat(items.count * 12)
        offset = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.timingCurve(0.15, 0.85, 0.3, 1.0, duration: 2.5 + delay * 0.3)) {
                offset = -totalScroll
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5 + delay * 0.3) {
                stopped = true
                onStopped?()
            }
        }
    }
}
