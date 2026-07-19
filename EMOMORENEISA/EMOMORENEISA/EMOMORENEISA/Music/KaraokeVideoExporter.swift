import AVFoundation
import UIKit

/// Renders a saved song into a shareable 1080×1920 (9:16, Instagram-ready)
/// karaoke video: scene pictures as the background, the same synced lyric
/// treatment as the live karaoke screen (yellow sweep, red memory-queue
/// words), and a small brand watermark. Everything happens on-device from
/// data the app already has — mp3, whisper-aligned line timings, scene plan,
/// and the already-downloaded scene pictures.
///
/// `nonisolated`: the project defaults to MainActor isolation, but this is a
/// pure CPU pipeline — it must run on the global executor or the frame loop
/// freezes the UI (and the progress bar with it).
nonisolated struct KaraokeVideoExporter {

    /// Plain snapshot of everything a frame needs, assembled by the caller on
    /// the main actor so the render loop touches no actor-isolated state.
    struct Input {
        let title: String
        let durationSec: Int
        let audioData: Data
        /// (text, startSec, endSec, red word indices) per sung line.
        let lines: [TimedLine]
        /// Scene start times, in order — frame time → scene index.
        let sceneStarts: [Double]
        /// Scene index → picture (from `KaraokeSceneImages`, fully loaded).
        let images: [Int: UIImage]
    }

    struct TimedLine {
        let text: String
        let startSec: Double
        let endSec: Double
        let words: [ProxyClient.MusicWord]
        let redIndices: Set<Int>
    }

    enum ExportError: Error {
        case audioUnreadable
        case writerFailed
    }

    private static let width = 1080
    private static let height = 1920
    private static let fps = 24

    /// Builds the render input on the main actor (reads model state, computes
    /// highlight indices), so `export` itself stays actor-free.
    @MainActor
    static func makeInput(song: ProxyClient.MusicSong, images: [Int: UIImage], highlightTargets: [String]) -> Input {
        let effective: [(text: String, start: Double, end: Double, words: [ProxyClient.MusicWord])]
        if !song.lines.isEmpty {
            effective = song.lines.map { ($0.text, $0.startSec, $0.endSec, $0.words) }
        } else {
            // Same length-weighted fallback as the live karaoke view, for
            // songs generated before the alignment step shipped.
            let sung = song.lyrics
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }
            let total = Double(sung.reduce(0) { $0 + max(1, $1.count) })
            let duration = Double(song.durationSec)
            var t = duration * 0.05
            let singable = duration * 0.9
            effective = sung.map { text in
                let span = singable * Double(max(1, text.count)) / total
                defer { t += span }
                return (text, t, t + span, [])
            }
        }
        let lines = effective.map { text, start, end, words in
            TimedLine(
                text: text,
                startSec: start,
                endSec: end,
                words: words,
                redIndices: LyricsHighlight.indices(
                    in: LyricsHighlight.words(in: text),
                    matchingAny: highlightTargets
                )
            )
        }
        return Input(
            title: song.title,
            durationSec: song.durationSec,
            audioData: song.audioData,
            lines: lines,
            sceneStarts: song.scenes.map(\.startSec),
            images: images
        )
    }

    /// Renders the full video and returns the .mp4 file URL (in tmp).
    /// `progress` is called on an arbitrary thread with 0...1.
    static func export(_ input: Input, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        // 1. Audio source: the mp3 bytes written to a temp file.
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("karaoke-audio-\(UUID().uuidString).mp3")
        try input.audioData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioAsset = AVURLAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.audioUnreadable
        }
        let audioDuration = try await audioAsset.load(.duration).seconds
        let duration = min(max(audioDuration, 1), Double(max(input.durationSec, 1)) + 2)

        // 2. Writer: H.264 video + AAC audio into one mp4.
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFilename(input.title)).mp4")
        try? FileManager.default.removeItem(at: outURL)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(videoInput)

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        // Audio reader: mp3 → PCM sample buffers the AAC input can consume.
        let reader = try AVAssetReader(asset: audioAsset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(readerOutput)

        guard writer.startWriting() else { throw ExportError.writerFailed }
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        // 3. Frames + audio, interleaved. The writer throttles whichever
        // input runs ahead — feeding all video before any audio deadlocks it
        // (isReadyForMoreMediaData stays false waiting for audio), so each
        // frame also pumps audio samples up to the frame's timestamp.
        var audioDone = false
        func pumpAudio(upTo t: Double) {
            while !audioDone && audioInput.isReadyForMoreMediaData {
                guard reader.status == .reading,
                      let sample = readerOutput.copyNextSampleBuffer() else {
                    audioDone = true
                    audioInput.markAsFinished()
                    break
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if !audioInput.append(sample) || pts >= duration {
                    audioDone = true
                    audioInput.markAsFinished()
                    break
                }
                if pts > t { break }
            }
        }

        let renderer = FrameRenderer(input: input)
        let frameCount = Int(duration * Double(fps))
        for frame in 0..<frameCount {
            let t = Double(frame) / Double(fps)
            pumpAudio(upTo: t)
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 8_000_000)
                pumpAudio(upTo: t)
            }
            // Each frame allocates a full 1080x1920 bitmap plus attributed
            // strings/fonts via Objective-C bridging (UIGraphicsImageRenderer,
            // NSAttributedString). A tight loop with no suspension point can
            // run for hundreds of frames without ever draining those
            // autoreleased objects, ballooning memory until iOS jetsams the
            // app (this is what crashed ~20-30% into export). Draining once
            // per frame keeps peak memory flat regardless of song length.
            var appendFailed = false
            var writeFailed = false
            autoreleasepool {
                guard let pool = adaptor.pixelBufferPool,
                      let buffer = makePixelBuffer(pool: pool) else { writeFailed = true; return }
                renderer.draw(at: t, into: buffer)
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
                if !adaptor.append(buffer, withPresentationTime: time) { appendFailed = true }
            }
            if writeFailed || appendFailed { throw ExportError.writerFailed }
            progress(0.92 * Double(frame) / Double(frameCount))
        }
        videoInput.markAsFinished()

        // Drain whatever audio remains (pumpAudio marks itself finished at
        // end-of-stream or once samples pass the video's end).
        while !audioDone {
            pumpAudio(upTo: duration)
            if !audioDone { try await Task.sleep(nanoseconds: 8_000_000) }
        }
        reader.cancelReading()
        progress(0.96)

        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.writerFailed }
        progress(1)
        return outURL
    }

    private static func safeFilename(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "professor-madrid-song" : cleaned
    }

    private static func makePixelBuffer(pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}

/// Draws one video frame. Mirrors MusicKaraokeView's look: aspect-filled
/// scene picture (dark-gradient fallback), darkening overlay, prev/current/
/// next lyric lines with the yellow sung-sweep and red queue-word highlight,
/// plus title and watermark.
private nonisolated final class FrameRenderer {
    private let input: KaraokeVideoExporter.Input
    private let size = CGSize(width: 1080, height: 1920)
    private let renderer: UIGraphicsImageRenderer
    private var lastSceneIndex = -2
    private var previousBackground: UIImage? = nil
    private var currentBackground: UIImage? = nil
    private var currentSceneStartSec: Double = 0
    /// Live karaoke gets this crossfade for free from SwiftUI's `.transition`
    /// (MusicKaraokeView.background) — the frame-by-frame exporter has to
    /// blend it manually.
    private static let crossfadeDuration: Double = 0.2

    /// Fixed slot height for every lyric line in the scroll "reel" — sized to
    /// comfortably fit 2 lines at the current-line font size. A fixed height
    /// (vs. measuring each line) keeps the per-line position a cheap `i *
    /// rowHeight` instead of a running sum, which matters across up to
    /// ~3600 frames for a long song.
    private static let rowHeight: CGFloat = 240
    /// Matches the live view's `.easeInOut(duration: 0.35)` scroll glide —
    /// there's no animation system here, so this window is eased by hand
    /// (smoothstep) as a function of elapsed time since the line started.
    private static let transitionDuration: Double = 0.35

    private struct LineAttrCache {
        let adjacent: NSAttributedString
        let adjacentHeight: CGFloat
        let currentWhite: NSAttributedString
        let currentYellow: NSAttributedString
        let currentHeight: CGFloat
        let introDimmed: NSAttributedString
    }
    /// Built once on first use (not per frame) — text/redIndices per line
    /// never change across the export, only which row is "current" does.
    private var lineCache: [LineAttrCache] = []

    init(input: KaraokeVideoExporter.Input) {
        self.input = input
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        self.renderer = UIGraphicsImageRenderer(size: size, format: format)
    }

    func draw(at t: TimeInterval, into buffer: CVPixelBuffer) {
        let image = renderer.image { ctx in
            drawBackground(at: t, in: ctx.cgContext)
            drawLyrics(at: t)
            drawChrome()
        }
        blit(image, into: buffer)
    }

    // MARK: Background

    private func sceneIndex(at t: TimeInterval) -> Int? {
        guard !input.sceneStarts.isEmpty else { return nil }
        return input.sceneStarts.lastIndex { t >= $0 } ?? 0
    }

    private func drawBackground(at t: TimeInterval, in cg: CGContext) {
        let idx = sceneIndex(at: t) ?? -1
        if idx != lastSceneIndex {
            previousBackground = currentBackground
            lastSceneIndex = idx
            currentBackground = composedBackground(sceneIndex: idx)
            currentSceneStartSec = (idx >= 0 && idx < input.sceneStarts.count) ? input.sceneStarts[idx] : t
        }
        let progress = min(1, max(0, (t - currentSceneStartSec) / Self.crossfadeDuration))
        if progress < 1, let previousBackground {
            previousBackground.draw(in: CGRect(origin: .zero, size: size))
            currentBackground?.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: progress)
        } else {
            currentBackground?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Picture aspect-filled + the same top/bottom darkening gradient as the
    /// live screen; deep-indigo gradient when the scene has no picture.
    private func composedBackground(sceneIndex idx: Int) -> UIImage {
        renderer.image { ctx in
            let cg = ctx.cgContext
            if idx >= 0, let image = input.images[idx] {
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let w = image.size.width * scale
                let h = image.size.height * scale
                image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            } else {
                let colors = [
                    UIColor(red: 0.18, green: 0.11, blue: 0.31, alpha: 1).cgColor,
                    UIColor(red: 0.07, green: 0.06, blue: 0.18, alpha: 1).cgColor
                ]
                if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
            }
            // Darkening overlay so white text reads on any picture.
            let stops: [(CGFloat, CGFloat)] = [(0, 0.55), (0.35, 0.15), (0.6, 0.25), (1, 0.82)]
            let overlayColors = stops.map { UIColor.black.withAlphaComponent($0.1).cgColor }
            let locations = stops.map { $0.0 }
            if let gradient = CGGradient(colorsSpace: nil, colors: overlayColors as CFArray, locations: locations) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: Lyrics

    /// Unlike the live view's `Int?` (nil during the instrumental intro),
    /// this always resolves to a row — row 0 doubles as the intro's dimmed
    /// preview slot (see `drawLyrics`), which keeps the reel math (always a
    /// concrete row index) simple.
    private func lineIndex(at t: TimeInterval) -> Int {
        guard !input.lines.isEmpty else { return 0 }
        return input.lines.lastIndex { t >= $0.startSec } ?? 0
    }

    private func rounded(_ pointSize: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: pointSize, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: pointSize)
        }
        return base
    }

    private func attributed(_ text: String, font: UIFont, base: UIColor, redIndices: Set<Int>) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: 2)

        let words = text.split(separator: " ").map(String.init)
        let result = NSMutableAttributedString()
        for (i, word) in words.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: " ")) }
            let red = UIColor(red: 1.0, green: 0.22, blue: 0.34, alpha: 1)
            result.append(NSAttributedString(string: word, attributes: [
                .font: font,
                .foregroundColor: redIndices.contains(i) ? red : base,
                .paragraphStyle: style,
                .shadow: shadow
            ]))
        }
        return result
    }

    private func ensureLineCache() {
        guard lineCache.isEmpty, !input.lines.isEmpty else { return }
        let hPadding: CGFloat = 70
        let maxWidth = size.width - hPadding * 2
        let currentFont = rounded(86, .heavy)
        let adjacentFont = rounded(52, .bold)
        func height(_ s: NSAttributedString) -> CGFloat {
            ceil(s.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin], context: nil).height)
        }
        lineCache = input.lines.map { line in
            let adjacent = attributed(line.text, font: adjacentFont, base: .white.withAlphaComponent(0.85), redIndices: [])
            let white = attributed(line.text, font: currentFont, base: .white, redIndices: line.redIndices)
            let yellow = attributed(line.text, font: currentFont, base: .systemYellow, redIndices: line.redIndices)
            let intro = attributed(line.text, font: currentFont, base: .white.withAlphaComponent(0.65), redIndices: [])
            return LineAttrCache(
                adjacent: adjacent, adjacentHeight: height(adjacent),
                currentWhite: white, currentYellow: yellow, currentHeight: height(white),
                introDimmed: intro
            )
        }
    }

    /// Manual per-frame equivalent of the live view's `withAnimation`-driven
    /// scroll: eases the reel's vertical offset from the previous line's
    /// centered position to the new one over `transitionDuration` seconds
    /// right after each line's `startSec`, using a smoothstep curve.
    private func scrollY(currentIdx: Int, at t: TimeInterval) -> CGFloat {
        let targetY = CGFloat(currentIdx) * Self.rowHeight
        guard currentIdx > 0 else { return targetY }
        let elapsed = t - input.lines[currentIdx].startSec
        guard elapsed >= 0, elapsed < Self.transitionDuration else { return targetY }
        let fromY = CGFloat(currentIdx - 1) * Self.rowHeight
        let p = CGFloat(elapsed / Self.transitionDuration)
        let eased = p * p * (3 - 2 * p) // smoothstep
        return fromY + (targetY - fromY) * eased
    }

    /// Draws the lyric "reel" — every line lives at a fixed `i * rowHeight`
    /// position; only the scroll offset animates, so no line's styling is
    /// ever inserted/removed mid-transition (that was the source of the
    /// overlapping/ghosted look in the previous discrete-swap version).
    /// Same "3 lines visible" content as before (current ± 1 neighbour) —
    /// only the transition mechanism changed.
    private func drawLyrics(at t: TimeInterval) {
        guard !input.lines.isEmpty else { return }
        ensureLineCache()
        let currentIdx = lineIndex(at: t)
        let isIntro = t < input.lines[0].startSec
        let hPadding: CGFloat = 70
        let maxWidth = size.width - hPadding * 2
        let offset = scrollY(currentIdx: currentIdx, at: t)
        let viewportCenterY = size.height / 2

        let lo = max(0, currentIdx - 1)
        let hi = min(input.lines.count - 1, currentIdx + 1)
        guard lo <= hi else { return }
        for i in lo...hi {
            let distance = i - currentIdx
            let rowCenterY = viewportCenterY + (CGFloat(i) * Self.rowHeight - offset)
            let cache = lineCache[i]

            if distance == 0 {
                let text = isIntro ? cache.introDimmed : cache.currentWhite
                let rect = CGRect(x: hPadding, y: rowCenterY - cache.currentHeight / 2, width: maxWidth, height: cache.currentHeight)
                text.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
                if !isIntro {
                    let line = input.lines[i]
                    let fraction = LyricsHighlight.sungFraction(words: line.words, lineStart: line.startSec, lineEnd: line.endSec, at: t)
                    if fraction > 0, let cg = UIGraphicsGetCurrentContext() {
                        cg.saveGState()
                        cg.clip(to: CGRect(x: hPadding, y: rect.minY, width: maxWidth * fraction, height: cache.currentHeight))
                        cache.currentYellow.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
                        cg.restoreGState()
                    }
                }
            } else {
                let rect = CGRect(x: hPadding, y: rowCenterY - cache.adjacentHeight / 2, width: maxWidth, height: cache.adjacentHeight)
                cache.adjacent.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
            }
        }
    }

    // MARK: Title + watermark

    private func drawChrome() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 6

        let title = NSAttributedString(string: input.title, attributes: [
            .font: rounded(46, .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .paragraphStyle: style,
            .shadow: shadow
        ])
        title.draw(with: CGRect(x: 60, y: 110, width: size.width - 120, height: 130),
                   options: [.usesLineFragmentOrigin], context: nil)

        let watermark = NSAttributedString(string: "Professor Madrid 🐾 professormadrid.com", attributes: [
            .font: rounded(32, .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            .paragraphStyle: style,
            .shadow: shadow
        ])
        watermark.draw(with: CGRect(x: 60, y: size.height - 140, width: size.width - 120, height: 60),
                       options: [.usesLineFragmentOrigin], context: nil)
    }

    // MARK: Pixel buffer blit

    private func blit(_ image: UIImage, into buffer: CVPixelBuffer) {
        guard let cgImage = image.cgImage else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
}
