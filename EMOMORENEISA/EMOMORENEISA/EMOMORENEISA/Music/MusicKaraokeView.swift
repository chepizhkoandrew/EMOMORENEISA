import SwiftUI
import AVFoundation
import UIKit

// MARK: - Scene image resolver

/// Turns the server's storyboard into actual pictures, cheapest source first:
/// 1. a memory-queue word reuses the illustration already saved with its card;
/// 2. anything else goes through /v1/illustration (shared server-side cache,
///    so repeated subjects and other users' identical scenes cost nothing);
/// 3. scenes with the same spanish+english pair share one image by design.
/// Loading is progressive — karaoke starts immediately and pictures pop in.
@MainActor
@Observable
final class KaraokeSceneImages {
    private(set) var images: [Int: UIImage] = [:]
    private var loadTask: Task<Void, Never>? = nil

    func load(scenes: [ProxyClient.MusicScene], cards: [MemoryCard]) {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            // One fetch per distinct picture; fan the result out to every scene
            // index that uses it.
            var byKey: [String: [Int]] = [:]
            for (idx, scene) in scenes.enumerated() {
                byKey[Self.key(scene), default: []].append(idx)
            }
            for (idx, scene) in scenes.enumerated() {
                guard let self, !Task.isCancelled else { return }
                let key = Self.key(scene)
                guard byKey[key]?.first == idx else { continue } // already handled by twin
                var image = Self.cardImage(for: scene, cards: cards)
                if image == nil {
                    let english = scene.english.isEmpty ? scene.spanish : scene.english
                    if let illo = await ProxyClient.shared.fetchIllustration(spanish: scene.spanish, english: english) {
                        image = UIImage(data: illo.data)
                    }
                }
                if let image {
                    for i in byKey[key] ?? [] { self.images[i] = image }
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    /// Awaits the in-flight load (no-op when nothing is loading) — the video
    /// exporter needs every picture on hand before rendering frames.
    func waitUntilLoaded() async {
        await loadTask?.value
    }

    private static func key(_ scene: ProxyClient.MusicScene) -> String {
        "\(normalize(scene.spanish))|\(normalize(scene.english))"
    }

    /// The queue-word chips are exact card contents, so a normalized equality
    /// check finds the card whose picture already illustrates this scene.
    private static func cardImage(for scene: ProxyClient.MusicScene, cards: [MemoryCard]) -> UIImage? {
        let wanted = [scene.word, scene.spanish].map(normalize).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return nil }
        for card in cards {
            guard wanted.contains(normalize(card.content)), let url = card.illustrationURL else { continue }
            if let image = UIImage(contentsOfFile: url.path) { return image }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Karaoke player

/// Full-screen karaoke for a generated song: the storyboard pictures crossfade
/// behind the lyrics with a slow Ken Burns drift, and the current line fills
/// left-to-right in sync with the music. Everything is driven off the audio
/// player's clock, so seeking/pausing keeps pictures and text honest.
struct MusicKaraokeView: View {
    let song: ProxyClient.MusicSong
    let memoryCards: [MemoryCard]
    /// Owned by the presenting screen, which starts loading the moment the
    /// song is ready — by the time the user taps Play, most/all pictures are
    /// already downloaded instead of only starting on this view's appear.
    let sceneImages: KaraokeSceneImages
    /// When set, a share button appears beside the close control. The closure
    /// runs on the PRESENTER (karaoke dismisses itself first) so the share
    /// sheet isn't stacked on top of a fullScreenCover.
    var onShare: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVAudioPlayer? = nil
    @State private var isPlaying = false
    @State private var finished = false

    /// Server-timed lines when available; a length-weighted spread otherwise
    /// (songs generated before the alignment step shipped).
    private var lines: [ProxyClient.MusicLyricLine] {
        if !song.lines.isEmpty { return song.lines }
        let sung = song.lyrics
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }
        guard !sung.isEmpty else { return [] }
        let total = Double(sung.reduce(0) { $0 + max(1, $1.count) })
        let duration = Double(song.durationSec)
        var t = duration * 0.05
        let singable = duration * 0.9
        return sung.map { text in
            let span = singable * Double(max(1, text.count)) / total
            defer { t += span }
            return ProxyClient.MusicLyricLine(text: text, startSec: t, endSec: t + span, words: [])
        }
    }

    var body: some View {
        TimelineView(.animation) { _ in
            let t = player?.currentTime ?? 0
            ZStack {
                background(at: t)
                overlayGradient
                content(at: t)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: Background pictures

    private func sceneIndex(at t: TimeInterval) -> Int? {
        guard !song.scenes.isEmpty else { return nil }
        return song.scenes.lastIndex { t >= $0.startSec } ?? 0
    }

    /// The scene actually playing right now, only when it maps to a real
    /// memory-queue word (invented filler scenes carry `word == ""` and
    /// should neither highlight nor caption anything).
    private func activeQueueScene(at t: TimeInterval) -> ProxyClient.MusicScene? {
        guard let idx = sceneIndex(at: t) else { return nil }
        let scene = song.scenes[idx]
        return scene.word.isEmpty ? nil : scene
    }

    @ViewBuilder
    private func background(at t: TimeInterval) -> some View {
        GeometryReader { geo in
            if let idx = sceneIndex(at: t), let image = sceneImages.images[idx] {
                let scene = song.scenes[idx]
                let span = max(0.5, scene.endSec - scene.startSec)
                let progress = min(1, max(0, (t - scene.startSec) / span))
                // Alternate zoom direction per scene so consecutive pictures
                // never drift the same way twice.
                let zoom = idx.isMultiple(of: 2)
                    ? 1.06 + 0.10 * progress
                    : 1.16 - 0.10 * progress
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(zoom)
                    .clipped()
                    .id(idx)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.7), value: idx)
            } else {
                GameBackground()
            }
        }
        .ignoresSafeArea()
    }

    private var overlayGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.15), location: 0.35),
                .init(color: .black.opacity(0.25), location: 0.6),
                .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Foreground

    @ViewBuilder
    private func content(at t: TimeInterval) -> some View {
        VStack(spacing: 0) {
            header
            Spacer()
            lyricsBlock(at: t)
            Spacer()
            controls(at: t)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    /// Just the close control — the song-title/scene-caption chip was removed
    /// so the karaoke screen shows only its core elements (picture + lyrics).
    private var header: some View {
        HStack {
            Spacer()
            if let onShare {
                Button {
                    dismiss()
                    onShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
        }
    }

    private func lineIndex(at t: TimeInterval) -> Int? {
        let all = lines
        guard !all.isEmpty else { return nil }
        return all.lastIndex { t >= $0.startSec }
    }

    // Lyrics are the point of karaoke — size them to dominate the screen.
    // Prev/next stay legible (not near-invisible) since they're part of
    // following along, just clearly secondary to the current line.
    private static let currentLineSize: CGFloat = 38
    private static let adjacentLineSize: CGFloat = 24
    private static let adjacentLineOpacity: Double = 0.9

    // The vocabulary word being sung right now gets its own vivid color
    // (LyricsHighlight.highlightColor, shared with the static lyrics card),
    // independent of the yellow sweep — it's meant to draw the eye as "this
    // is the word from your queue", not to track singing progress. A blurred
    // glow was tried first and scrapped: at this font size the blur radius
    // needed to read as a "glow" instead smeared adjacent letters into an
    // illegible blob (confirmed on-device) — a plain saturated color reads
    // far better than any halo effect here.

    /// A crisp black outline behind the text — the standard technique for
    /// captions over an unpredictable photo, and a hard requirement here:
    /// the background pictures are pastel/light as often as they're dark, so
    /// yellow-on-cream or white-on-pale-blue was reading as barely visible.
    /// A soft drop shadow doesn't fix that (it fades exactly where a light
    /// background needs the most contrast); an actual outline does, in every
    /// case, regardless of what's behind it.
    private static let outlineOffsets: [CGSize] = {
        let r: CGFloat = 1.4
        let d = r * 0.72
        return [
            CGSize(width: -r, height: 0), CGSize(width: r, height: 0),
            CGSize(width: 0, height: -r), CGSize(width: 0, height: r),
            CGSize(width: -d, height: -d), CGSize(width: d, height: -d),
            CGSize(width: -d, height: d), CGSize(width: d, height: d)
        ]
    }()

    private static func outlinedText(_ text: Text, font: Font) -> some View {
        ZStack {
            ForEach(Array(outlineOffsets.enumerated()), id: \.offset) { _, o in
                text.font(font).foregroundColor(.black.opacity(0.95)).offset(o)
            }
        }
    }

    private func adjacentLine(_ text: String) -> some View {
        let font = Font.system(size: Self.adjacentLineSize, weight: .bold, design: .rounded)
        return ZStack {
            Self.outlinedText(Text(text), font: font)
            Text(text).font(font).foregroundColor(.white.opacity(Self.adjacentLineOpacity))
        }
    }

    @ViewBuilder
    private func lyricsBlock(at t: TimeInterval) -> some View {
        let all = lines
        let current = lineIndex(at: t)
        VStack(spacing: 20) {
            if let i = current, i > 0 {
                adjacentLine(all[i - 1].text)
            }
            if let i = current {
                karaokeLine(all[i], at: t)
                    .id("line-\(i)")
            } else if let first = all.first {
                // Instrumental intro: preview the opening line dimmed.
                let font = Font.system(size: Self.currentLineSize, weight: .heavy, design: .rounded)
                ZStack {
                    Self.outlinedText(Text(first.text), font: font)
                    Text(first.text).font(font).foregroundColor(.white.opacity(0.65))
                }
            }
            if let i = current, i + 1 < all.count {
                adjacentLine(all[i + 1].text)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: current)
    }

    /// Classic karaoke fill: the sung fraction of the current line sweeps
    /// left-to-right, interpolated linearly across the line's time span. The
    /// active queue word (if this line contains it) is carved out of both
    /// layers and re-drawn as its own solid-color layer instead — no blur,
    /// see `highlightColor` above for why.
    private func karaokeLine(_ line: ProxyClient.MusicLyricLine, at t: TimeInterval) -> some View {
        let fraction = LyricsHighlight.sungFraction(words: line.words, lineStart: line.startSec, lineEnd: line.endSec, at: t)
        let wordList = LyricsHighlight.words(in: line.text)
        let highlightPhrase = activeQueueScene(at: t)?.word ?? ""
        let highlightSet = LyricsHighlight.indices(in: wordList, matching: highlightPhrase)
        let font = Font.system(size: Self.currentLineSize, weight: .heavy, design: .rounded)

        let unsung = LyricsHighlight.composedText(wordList) { i, _ in highlightSet.contains(i) ? .clear : .white }
        let sung = LyricsHighlight.composedText(wordList) { i, _ in highlightSet.contains(i) ? .clear : .yellow }
        let highlight = highlightSet.isEmpty ? nil : LyricsHighlight.composedText(wordList) { i, _ in
            highlightSet.contains(i) ? LyricsHighlight.highlightColor : .clear
        }

        return ZStack {
            Self.outlinedText(Text(line.text), font: font)
            unsung.font(font)
            sung.font(font)
                .mask(
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * fraction)
                    }
                )
            // Same font as the white/yellow layers — a heavier weight here
            // changes glyph widths, so the red layer's line wrapping drifts
            // out of register and double-prints over neighboring words.
            if let highlight {
                highlight.font(font)
            }
        }
    }

    // MARK: Controls

    /// Spanish + translation for whatever queue word is actually sounding
    /// right now, sitting directly above the progress bar. Only visible
    /// while that word's scene is playing — it disappears the moment the
    /// scene moves on, same lifetime as the highlight in the lyric above.
    @ViewBuilder
    private func activeWordCaption(at t: TimeInterval) -> some View {
        if let scene = activeQueueScene(at: t) {
            HStack(spacing: 8) {
                Text(scene.word)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(LyricsHighlight.highlightColor)
                if !scene.english.isEmpty {
                    Text("—")
                        .foregroundColor(.white.opacity(0.4))
                    Text(scene.english)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke(LyricsHighlight.highlightColor.opacity(0.5), lineWidth: 1))
            .id("caption-\(scene.word)")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private func controls(at t: TimeInterval) -> some View {
        VStack(spacing: 14) {
            activeWordCaption(at: t)
                .animation(.easeInOut(duration: 0.3), value: activeQueueScene(at: t)?.word)
            progressBar
            HStack(spacing: 36) {
                Button {
                    player?.currentTime = 0
                    if !isPlaying { resume() }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button {
                    if isPlaying { pause() } else { resume() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 72, height: 72)
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                        Image(systemName: isPlaying ? "pause.fill" : (finished ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)

                // Symmetric spacer twin of the restart button.
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.clear)
            }
        }
    }

    private var progressBar: some View {
        let duration = max(1, player?.duration ?? Double(song.durationSec))
        let t = player?.currentTime ?? 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.yellow)
                    .frame(width: geo.size.width * min(1, t / duration))
            }
        }
        .frame(height: 4)
    }

    // MARK: Playback lifecycle

    private func start() {
        // Idempotent — a no-op if the presenting screen already kicked this
        // off, a safety net if this view is ever opened without preloading.
        sceneImages.load(scenes: song.scenes, cards: memoryCards)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = try? AVAudioPlayer(data: song.audioData)
        p?.prepareToPlay()
        player = p
        resume()
    }

    private func resume() {
        finished = false
        player?.play()
        isPlaying = true
        watchForEnd()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func stop() {
        // sceneImages is owned by the presenting screen — cancelling it here
        // would kill an in-flight preload if the user reopens karaoke.
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// AVAudioPlayer has no async completion; poll for the natural end so the
    /// play button flips to replay.
    private func watchForEnd() {
        Task { @MainActor in
            while let p = player, isPlaying {
                if !p.isPlaying {
                    isPlaying = false
                    finished = true
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}
