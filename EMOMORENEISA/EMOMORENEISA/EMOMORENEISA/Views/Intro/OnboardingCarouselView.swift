import SwiftUI
import AVFoundation

// Native-language suffix for the onboarding voice clips (English or Ukrainian).
private func onboardLangSuffix() -> String {
    switch LocalizationManager.shared.language {
    case .ukrainian: return "uk"
    case .english:   return "en"
    }
}

// MARK: - Main View

struct OnboardingCarouselView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isMuted = false
    private let totalPages = 5

    var body: some View {
        ZStack {
            GameBackground()
            DreamParticlesView().allowsHitTesting(false).ignoresSafeArea()

            TabView(selection: $page) {
                OnboardDogSlide(onNext: { withAnimation { page = 1 } })
                    .tag(0)
                OnboardStreetViewSlide(
                    onBack: { withAnimation { page = 0 } },
                    onNext: { withAnimation { page = 2 } }
                ).tag(1)
                OnboardConsistencySlide(
                    onBack: { withAnimation { page = 1 } },
                    onNext: { withAnimation { page = 3 } }
                ).tag(2)
                OnboardVerbsSlide(
                    onBack: { withAnimation { page = 2 } },
                    onNext: { withAnimation { page = 4 } }
                ).tag(3)
                OnboardCtaSlide(onFinish: onFinish).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            pageIndicator
            muteButton
        }
        .ignoresSafeArea()
        .onAppear {
            BackgroundMusicPlayer.shared.play()
            playVoice(for: page)
        }
        .onChange(of: page) { _, newPage in
            playVoice(for: newPage)
        }
        .onDisappear { OnboardAudioManager.shared.stop() }
    }

    // Voice is driven from the actual page selection (not each slide's
    // .onAppear): a paged TabView pre-renders neighbouring slides, firing their
    // .onAppear before they are visible, which made the wrong clip play. Keying
    // on `page` guarantees the clip matches the slide the user is looking at.
    private func playVoice(for page: Int) {
        let suffix = onboardLangSuffix()
        switch page {
        case 0:
            OnboardAudioManager.shared.play(named: "onboard_intro_\(suffix)")
        case 1:
            OnboardAudioManager.shared.play(named: "onboard_head_streetview_\(suffix)")
        case 2:
            OnboardAudioManager.shared.play(named: "onboard_head_consistency_\(suffix)")
        case 3:
            OnboardAudioManager.shared.play(named: "onboard_head_verbs_\(suffix)")
        case 4:
            let localized = suffix == "uk" ? "onboard_vamos_start_uk" : "onboard_vamos_start_en"
            OnboardAudioManager.shared.play(named: localized, fallback: "onboard_vamos_probar", volume: 0.9)
        default:
            break
        }
    }

    private var pageIndicator: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.yellow : Color.white.opacity(0.3))
                        .frame(width: i == page ? 20 : 7, height: 7)
                        .animation(.spring(response: 0.35), value: page)
                }
            }
            .padding(.bottom, 48)
        }
    }

    private var muteButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isMuted.toggle()
                    BackgroundMusicPlayer.shared.setMuted(isMuted)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .padding(.trailing, 18)
            }
            .padding(.top, 90)
            Spacer()
        }
    }
}

// MARK: - Slide 0: Dog intro

private struct OnboardDogSlide: View {
    let onNext: () -> Void

    private struct TypeSeg {
        let text: String
        let color: Color
        let size: CGFloat
        init(_ text: String, _ color: Color, _ size: CGFloat = 30) {
            self.text = text; self.color = color; self.size = size
        }
    }

    private let sentences: [[[TypeSeg]]] = [
        [
            [TypeSeg(L("This is the"), .white)],
            [TypeSeg(L("app for learning"), .yellow)],
            [TypeSeg(L("Spanish.."), .yellow)]
        ],
        [
            [TypeSeg(L("It uses "), .white), TypeSeg(L("dog"), .yellow)],
            [TypeSeg(L("training techniques."), .yellow)],
            [TypeSeg(L("¡Gauwau!"), .white)]
        ],
        [
            [TypeSeg(L("And "), .white), TypeSeg(L("NLP"), .yellow), TypeSeg(L(" techniques"), .white)],
            [TypeSeg(L("for"), .white)],
            [TypeSeg(L("BETTER"), Color(red: 1.0, green: 0.75, blue: 0.0), 34)],
            [TypeSeg(L("REMEMBERING.."), Color(red: 1.0, green: 0.75, blue: 0.0), 34)]
        ],
        [
            [TypeSeg(L("Created by human."), .white)]
        ]
    ]

    @State private var sentIdx = 0
    @State private var rowIdx = 0
    @State private var charCount = 0
    @State private var cursorOn = true
    @State private var typingTask: Task<Void, Never>? = nil
    @State private var cursorTask: Task<Void, Never>? = nil
    @State private var allDone = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        Spacer()
                        Image("onboard_dog")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(geo.size.width * 0.78, 360))
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + 16)
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        let sent = sentences[min(sentIdx, sentences.count - 1)]
                        ForEach(0..<sent.count, id: \.self) { r in
                            let row = sent[min(r, sent.count - 1)]
                            if r < rowIdx {
                                Text(rowAttr(row, chars: nil, cursorColor: .clear))
                                    .font(.system(size: 30, weight: .black, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if r == rowIdx {
                                ZStack(alignment: .leading) {
                                    Text(rowAttr(row, chars: nil, cursorColor: .clear))
                                        .font(.system(size: 30, weight: .black, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .opacity(0)
                                    Text(rowAttr(row, chars: charCount, cursorColor: cursorOn ? .yellow : .clear))
                                        .font(.system(size: 30, weight: .black, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                Text(rowAttr(row, chars: nil, cursorColor: .clear))
                                    .font(.system(size: 30, weight: .black, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .opacity(0)
                            }
                        }
                    }
                    .frame(maxWidth: geo.size.width * 0.82, alignment: .leading)
                    .padding(.horizontal, 24)
                    Spacer()
                    Color.clear.frame(height: geo.size.height * 0.46)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { advanceOrSkip() }
        }
        .ignoresSafeArea()
        .onAppear { resetAndStart() }
        .onDisappear {
            typingTask?.cancel(); typingTask = nil
            cursorTask?.cancel(); cursorTask = nil
            sentIdx = 0; rowIdx = 0; charCount = 0; allDone = false
        }
    }

    private func rowAttr(_ row: [TypeSeg], chars: Int?, cursorColor: Color) -> AttributedString {
        var result = AttributedString()
        var remaining = chars ?? Int.max
        for seg in row {
            let take = min(remaining, seg.text.count)
            if take <= 0 { break }
            var part = AttributedString(String(seg.text.prefix(take)))
            part.foregroundColor = seg.color
            part.font = .system(size: seg.size, weight: .black, design: .rounded)
            result += part
            remaining -= take
        }
        var cur = AttributedString("|")
        cur.foregroundColor = cursorColor
        cur.font = .system(size: 30, weight: .black, design: .rounded)
        result += cur
        return result
    }

    private func charAt(row: [TypeSeg], idx: Int) -> Character {
        var i = idx
        for seg in row {
            if i < seg.text.count {
                return seg.text[seg.text.index(seg.text.startIndex, offsetBy: i)]
            }
            i -= seg.text.count
        }
        return " "
    }

    private func rowTotal(_ row: [TypeSeg]) -> Int {
        row.reduce(0) { $0 + $1.text.count }
    }

    private func resetAndStart() {
        typingTask?.cancel(); cursorTask?.cancel()
        sentIdx = 0; rowIdx = 0; charCount = 0; allDone = false
        startCursor()
        typingTask = Task { @MainActor in await typeCurrentRow() }
    }

    private func advanceSkip() {
        typingTask?.cancel()
        let sent = sentences[min(sentIdx, sentences.count - 1)]
        let row = sent[min(rowIdx, sent.count - 1)]
        charCount = rowTotal(row)
        typingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await advanceRow()
        }
    }

    private func advanceOrSkip() {
        if allDone { onNext(); return }
        advanceSkip()
    }

    private func startCursor() {
        cursorTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                cursorOn.toggle()
            }
        }
    }

    @MainActor
    private func typeCurrentRow() async {
        let si = sentIdx
        let ri = rowIdx
        guard si < sentences.count, ri < sentences[si].count else {
            withAnimation { allDone = true }
            return
        }
        let row = sentences[si][ri]
        let total = rowTotal(row)

        while charCount < total {
            guard !Task.isCancelled else { return }
            let ch = charAt(row: row, idx: charCount)
            charCount += 1
            let delay: UInt64
            if "!?".contains(ch) { delay = 280_000_000 }
            else if ".".contains(ch) { delay = 200_000_000 }
            else if ",;:".contains(ch) { delay = 100_000_000 }
            else { delay = UInt64(Double.random(in: 0.04...0.075) * 1_000_000_000) }
            try? await Task.sleep(nanoseconds: delay)
        }

        try? await Task.sleep(nanoseconds: 750_000_000)
        guard !Task.isCancelled else { return }
        await advanceRow()
    }

    @MainActor
    private func advanceRow() async {
        let si = sentIdx
        let ri = rowIdx
        guard si < sentences.count else { return }
        let sent = sentences[si]

        if ri < sent.count - 1 {
            rowIdx += 1
            charCount = 0
            guard !Task.isCancelled else { return }
            await typeCurrentRow()
        } else {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            if si < sentences.count - 1 {
                sentIdx += 1
                rowIdx = 0
                charCount = 0
                guard !Task.isCancelled else { return }
                await typeCurrentRow()
            } else {
                withAnimation { allDone = true }
            }
        }
    }

}

// MARK: - Slide background particles

private struct OnboardBgParticleItem: View {
    let imageName: String
    let size: CGFloat
    let floatAmp: CGFloat
    let rotAmp: Double
    let duration: Double
    let delay: Double

    @State private var floatY: CGFloat = 0
    @State private var rot: Double = 0
    @State private var opacity: Double = 0

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size)
            .rotationEffect(.degrees(rot))
            .offset(y: floatY)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.7).delay(delay)) {
                    opacity = 0.20
                }
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    floatY = -floatAmp
                    rot = rotAmp
                }
            }
            .onDisappear {
                opacity = 0
                floatY = 0
                rot = 0
            }
    }
}

private struct OnboardSlideParticles: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Group {
                OnboardBgParticleItem(imageName: "dream_hotdog",        size: 52, floatAmp: 14, rotAmp:  10, duration: 5.5, delay: 0.0)
                    .position(x: w * 0.12, y: h * 0.68)
                OnboardBgParticleItem(imageName: "dream_chicken_fried", size: 60, floatAmp: 18, rotAmp: -12, duration: 4.8, delay: 1.3)
                    .position(x: w * 0.82, y: h * 0.72)
                OnboardBgParticleItem(imageName: "dream_pasta",         size: 48, floatAmp: 12, rotAmp:   8, duration: 6.0, delay: 2.5)
                    .position(x: w * 0.50, y: h * 0.78)
                OnboardBgParticleItem(imageName: "dream_seagull",       size: 56, floatAmp: 16, rotAmp: -10, duration: 5.2, delay: 0.9)
                    .position(x: w * 0.88, y: h * 0.62)
            }
        }
    }
}

// MARK: - Slide 1: Street view

private struct OnboardStreetViewSlide: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var headerVisible = false
    @State private var textVisible = false
    @State private var imageVisible = false
    @State private var appeared = false

    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.78)
    private static let itemIn = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OnboardSlideParticles().allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()
                    Image("street_view")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: geo.size.height * 0.32)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                        .padding(.horizontal, 16)
                        .offset(y: imageVisible ? 0 : 50)
                        .opacity(imageVisible ? 1 : 0)
                        .animation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.3), value: imageVisible)
                    Spacer().frame(height: 62)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    if headerVisible {
                        Text("01")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.6))
                            .tracking(3)
                            .transition(Self.itemIn)
                        Text(L("Street view -\nlearn anywhere!"))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .transition(Self.itemIn)
                    }
                    if textVisible {
                        Color.clear.frame(height: 20)
                        listRow("1.") { mixedText(yellow: L("Take a picture"), normal: L(" of what you see around")) }
                            .transition(Self.itemIn)
                        listRow("2.") {
                            Text(L("Professor will give you words to describe it"))
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        listRow("3.") {
                            Text(L("Talk with professor about it"))
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        mixedText(
                            yellow: L("This is how children do"),
                            normal: L(" - they remember what they see!\nAnd they always have someone to talk about it.")
                        )
                        .transition(Self.itemIn)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Self.spring, value: headerVisible)
                .animation(Self.spring, value: textVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if value.startLocation.x < 110 { onBack() } else { tapReveal() }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !appeared else { return }
            appeared = true
            headerVisible = false; textVisible = false; imageVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard appeared else { return }
                withAnimation(Self.spring) { headerVisible = true }
                imageVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard appeared else { return }
                withAnimation(.easeIn(duration: 0.5)) { textVisible = true }
            }
        }
        .onDisappear { appeared = false; headerVisible = false; textVisible = false; imageVisible = false }
    }

    private func tapReveal() { onNext() }

    @ViewBuilder
    private func listRow<C: View>(_ number: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .frame(width: 28, alignment: .leading)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mixedText(yellow: String, normal: String) -> some View {
        var a = AttributedString(yellow)
        a.font = .system(size: 20, weight: .black, design: .rounded)
        a.foregroundColor = .yellow
        var b = AttributedString(normal)
        b.font = .system(size: 20, weight: .medium, design: .rounded)
        b.foregroundColor = .init(.white.opacity(0.60))
        return Text(a + b).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Slide 2: Consistency

private struct OnboardConsistencySlide: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var headerVisible = false
    @State private var textVisible = false
    @State private var imageVisible = false
    @State private var appeared = false

    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.78)
    private static let itemIn = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OnboardSlideParticles().allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()
                    Image("progress_screen")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: geo.size.height * 0.32)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                        .padding(.horizontal, 16)
                        .offset(y: imageVisible ? 0 : 50)
                        .opacity(imageVisible ? 1 : 0)
                        .animation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.3), value: imageVisible)
                    Spacer().frame(height: 62)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    if headerVisible {
                        Text("02")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.6))
                            .tracking(3)
                            .transition(Self.itemIn)
                        Text(L("Consistency\nis the trick"))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .transition(Self.itemIn)
                    }
                    if textVisible {
                        Color.clear.frame(height: 20)
                        listRow("1.") { mixedText(normal: L("While learning - you will build list of "), yellow: L("words to remember")) }
                            .transition(Self.itemIn)
                        listRow("2.") { triText(normal: L("Seagull builds "), yellow2: L("smart schedule"), normal2: L(" for you")) }
                            .transition(Self.itemIn)
                        listRow("3.") {
                            Text(L("2 clicks → start practicing"))
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        triText(yellow: L("This is how dogs learn"), normal: L(" to ride a bicycle.. Your Spanish is way easier, "), yellow2: L("you can do it!"))
                            .transition(Self.itemIn)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 110)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Self.spring, value: headerVisible)
                .animation(Self.spring, value: textVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if value.startLocation.x < 110 { onBack() } else { tapReveal() }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !appeared else { return }
            appeared = true
            headerVisible = false; textVisible = false; imageVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard appeared else { return }
                withAnimation(Self.spring) { headerVisible = true }
                imageVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard appeared else { return }
                withAnimation(.easeIn(duration: 0.5)) { textVisible = true }
            }
        }
        .onDisappear { appeared = false; headerVisible = false; textVisible = false; imageVisible = false }
    }

    private func tapReveal() { onNext() }

    @ViewBuilder
    private func listRow<C: View>(_ number: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .frame(width: 28, alignment: .leading)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mixedText(normal: String = "", yellow: String = "") -> some View {
        var a = AttributedString(normal)
        a.font = .system(size: 20, weight: .medium, design: .rounded)
        a.foregroundColor = .init(.white.opacity(0.82))
        var b = AttributedString(yellow)
        b.font = .system(size: 20, weight: .black, design: .rounded)
        b.foregroundColor = .yellow
        return Text(a + b).fixedSize(horizontal: false, vertical: true)
    }

    private func triText(yellow: String = "", normal: String = "", yellow2: String = "", normal2: String = "") -> some View {
        var a = AttributedString(yellow)
        a.font = .system(size: 20, weight: .black, design: .rounded)
        a.foregroundColor = .yellow
        var b = AttributedString(normal)
        b.font = .system(size: 20, weight: .medium, design: .rounded)
        b.foregroundColor = .init(.white.opacity(0.60))
        var c = AttributedString(yellow2)
        c.font = .system(size: 20, weight: .black, design: .rounded)
        c.foregroundColor = .yellow
        var d = AttributedString(normal2)
        d.font = .system(size: 20, weight: .medium, design: .rounded)
        d.foregroundColor = .init(.white.opacity(0.82))
        return Text(a + b + c + d).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Slide 3: Verbs

private struct OnboardVerbsSlide: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var headerVisible = false
    @State private var textVisible = false
    @State private var imageVisible = false
    @State private var appeared = false

    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.78)
    private static let itemIn = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OnboardSlideParticles().allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer()
                    Image("verb_game")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: geo.size.height * 0.32)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                        .padding(.horizontal, 16)
                        .offset(y: imageVisible ? 0 : 50)
                        .opacity(imageVisible ? 1 : 0)
                        .animation(.spring(response: 0.65, dampingFraction: 0.8).delay(0.3), value: imageVisible)
                    Spacer().frame(height: 62)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    if headerVisible {
                        Text("03")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow.opacity(0.6))
                            .tracking(3)
                            .transition(Self.itemIn)
                        Text(L("Verbs and times\nis 80% of Spanish"))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .transition(Self.itemIn)
                    }
                    if textVisible {
                        Color.clear.frame(height: 20)
                        listRow("1.") {
                            Text(L("Practice verbally, this is NLP"))
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        listRow("2.") {
                            Text("Yo como, tu comes, el/ella come..")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        listRow("3.") {
                            Text(L("Train reaction, not the knowledge"))
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .transition(Self.itemIn)
                        fourText(
                            yellow: L("This is how sportsmen do"),
                            normal: L(", maximise number of verbal repetitions, because your goal is to "),
                            yellow2: L("SPEAK SPANISH"),
                            normal2: L(" (not just to know it)")
                        )
                        .transition(Self.itemIn)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Self.spring, value: headerVisible)
                .animation(Self.spring, value: textVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if value.startLocation.x < 110 { onBack() } else { tapReveal() }
                    }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            guard !appeared else { return }
            appeared = true
            headerVisible = false; textVisible = false; imageVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard appeared else { return }
                withAnimation(Self.spring) { headerVisible = true }
                imageVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard appeared else { return }
                withAnimation(.easeIn(duration: 0.5)) { textVisible = true }
            }
        }
        .onDisappear { appeared = false; headerVisible = false; textVisible = false; imageVisible = false }
    }

    private func tapReveal() { onNext() }

    @ViewBuilder
    private func listRow<C: View>(_ number: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
                .frame(width: 28, alignment: .leading)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fourText(yellow: String, normal: String, yellow2: String, normal2: String) -> some View {
        var a = AttributedString(yellow)
        a.font = .system(size: 20, weight: .black, design: .rounded)
        a.foregroundColor = .yellow
        var b = AttributedString(normal)
        b.font = .system(size: 20, weight: .medium, design: .rounded)
        b.foregroundColor = .init(.white.opacity(0.60))
        var c = AttributedString(yellow2)
        c.font = .system(size: 20, weight: .black, design: .rounded)
        c.foregroundColor = .yellow
        var d = AttributedString(normal2)
        d.font = .system(size: 20, weight: .medium, design: .rounded)
        d.foregroundColor = .init(.white.opacity(0.60))
        return Text(a + b + c + d).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - CTA slide

private struct OnboardCtaSlide: View {
    let onFinish: () -> Void

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    Image("professor_dog")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)

                    Text("¡Vamos a probar!")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .yellow.opacity(0.4), radius: 12)

                    Button(action: { onFinish() }) {
                        Text(L("Let's try"))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .yellow.opacity(0.5), radius: 16)
                    }
                    .padding(.horizontal, 32)

                    Color.clear.frame(height: geo.safeAreaInsets.bottom + 50)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
    }
}


