import AVFoundation
import UIKit

/// Renders a saved song into a shareable 1080×1920 (9:16, Instagram-ready)
/// karaoke video: scene pictures as the background, the same synced lyric
/// treatment as the live karaoke screen (yellow sweep, red memory-queue
/// words), and a small brand watermark. Everything happens on-device from
/// data the app already has — mp3, whisper-aligned line timings, scene plan,
/// and the already-downloaded scene pictures.
struct KaraokeVideoExporter {

    struct Input {
        let song: ProxyClient.MusicSong
        /// Scene index → picture, from `KaraokeSceneImages` (fully loaded).
        let images: [Int: UIImage]
        /// Words to paint red wherever they appear (picked words + scene words).
        let highlightTargets: [String]
    }

    enum ExportError: Error {
        case audioUnreadable
        case writerFailed
    }

    private static let width = 1080
    private static let height = 1920
    private static let fps = 24

    /// Renders the full video and returns the .mp4 file URL (in tmp).
    /// `progress` is called on an arbitrary thread with 0...1.
    static func export(_ input: Input, progress: @escaping (Double) -> Void) async throws -> URL {
        // 1. Audio source: the mp3 bytes written to a temp file.
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("karaoke-audio-\(UUID().uuidString).mp3")
        try input.song.audioData.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioAsset = AVURLAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.audioUnreadable
        }
        let audioDuration = try await audioAsset.load(.duration).seconds
        let duration = min(max(audioDuration, 1), Double(max(input.song.durationSec, 1)) + 2)

        // 2. Writer: H.264 video + AAC audio into one mp4.
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFilename(input.song.title)).mp4")
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

        // 3. Video frames.
        let renderer = FrameRenderer(input: input)
        let frameCount = Int(duration * Double(fps))
        for frame in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 8_000_000)
            }
            let t = Double(frame) / Double(fps)
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = makePixelBuffer(pool: pool) else { throw ExportError.writerFailed }
            renderer.draw(at: t, into: buffer)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            if !adaptor.append(buffer, withPresentationTime: time) { throw ExportError.writerFailed }
            // Frames are ~90% of the work; audio + finalize take the rest.
            progress(0.9 * Double(frame) / Double(frameCount))
        }
        videoInput.markAsFinished()

        // 4. Audio samples.
        while reader.status == .reading {
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 8_000_000)
            }
            if let sample = readerOutput.copyNextSampleBuffer() {
                if CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) > duration { break }
                if !audioInput.append(sample) { break }
            } else {
                break
            }
        }
        audioInput.markAsFinished()
        reader.cancelReading()
        progress(0.95)

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
private final class KaraokeFrameRendererState {
    var lastSceneIndex: Int = -1
    var cachedBackground: UIImage? = nil
}

private struct FrameRenderer {
    let input: KaraokeVideoExporter.Input
    private let size = CGSize(width: 1080, height: 1920)
    private let renderer: UIGraphicsImageRenderer
    private let state = KaraokeFrameRendererState()
    private let lines: [ProxyClient.MusicLyricLine]

    init(input: KaraokeVideoExporter.Input) {
        self.input = input
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        self.renderer = UIGraphicsImageRenderer(size: size, format: format)
        self.lines = Self.effectiveLines(for: input.song)
    }

    /// Same fallback as the live karaoke view: server-timed lines when
    /// available, otherwise a length-weighted spread across the duration.
    private static func effectiveLines(for song: ProxyClient.MusicSong) -> [ProxyClient.MusicLyricLine] {
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
            return ProxyClient.MusicLyricLine(text: text, startSec: t, endSec: t + span)
        }
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
        guard !input.song.scenes.isEmpty else { return nil }
        return input.song.scenes.lastIndex { t >= $0.startSec } ?? 0
    }

    private func drawBackground(at t: TimeInterval, in cg: CGContext) {
        let idx = sceneIndex(at: t) ?? -1
        if idx != state.lastSceneIndex {
            state.lastSceneIndex = idx
            state.cachedBackground = composedBackground(sceneIndex: idx)
        }
        state.cachedBackground?.draw(in: CGRect(origin: .zero, size: size))
    }

    /// Picture aspect-filled + the same top/bottom darkening gradient as the
    /// live screen; deep-indigo gradient when the scene has no picture.
    private func composedBackground(sceneIndex idx: Int) -> UIImage {
        renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
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
            let overlayStops: [(CGFloat, CGFloat)] = [(0, 0.55), (0.35, 0.15), (0.6, 0.25), (1, 0.82)]
            let overlayColors = overlayStops.map { UIColor.black.withAlphaComponent($0.1).cgColor }
            let locations = overlayStops.map { $0.0 }
            if let gradient = CGGradient(colorsSpace: nil, colors: overlayColors as CFArray, locations: locations) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            _ = rect
        }
    }

    // MARK: Lyrics

    private func lineIndex(at t: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        return lines.lastIndex { t >= $0.startSec }
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

        let words = LyricsHighlight.words(in: text)
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

    private func drawLyrics(at t: TimeInterval) {
        guard !lines.isEmpty else { return }
        let currentIdx = lineIndex(at: t)
        let hPadding: CGFloat = 70
        let maxWidth = size.width - hPadding * 2
        let currentFont = rounded(86, .heavy)
        let adjacentFont = rounded(52, .bold)

        var blocks: [(NSAttributedString, NSAttributedString?, Double)] = []

        if let i = currentIdx {
            if i > 0 {
                blocks.append((attributed(lines[i - 1].text, font: adjacentFont,
                                          base: .white.withAlphaComponent(0.85), redIndices: []), nil, 0))
            }
            let line = lines[i]
            let redSet = LyricsHighlight.indices(
                in: LyricsHighlight.words(in: line.text),
                matchingAny: input.highlightTargets
            )
            let span = max(0.2, line.endSec - line.startSec)
            let fraction = min(1, max(0, (t - line.startSec) / span))
            let white = attributed(line.text, font: currentFont, base: .white, redIndices: redSet)
            let yellow = attributed(line.text, font: currentFont, base: .systemYellow, redIndices: redSet)
            blocks.append((white, yellow, fraction))
            if i + 1 < lines.count {
                blocks.append((attributed(lines[i + 1].text, font: adjacentFont,
                                          base: .white.withAlphaComponent(0.85), redIndices: []), nil, 0))
            }
        } else if let first = lines.first {
            // Instrumental intro: dimmed preview of the opening line.
            blocks.append((attributed(first.text, font: currentFont,
                                      base: .white.withAlphaComponent(0.65), redIndices: []), nil, 0))
        }

        let spacing: CGFloat = 44
        let heights = blocks.map {
            ceil($0.0.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin], context: nil).height)
        }
        let totalHeight = heights.reduce(0, +) + spacing * CGFloat(max(0, blocks.count - 1))
        var y = (size.height - totalHeight) / 2

        for (index, block) in blocks.enumerated() {
            let rect = CGRect(x: hPadding, y: y, width: maxWidth, height: heights[index])
            block.0.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
            // Sung sweep: the yellow copy clipped to the sung fraction, same
            // whole-block sweep as the live karaoke mask.
            if let sungCopy = block.1, block.2 > 0, let cg = UIGraphicsGetCurrentContext() {
                cg.saveGState()
                cg.clip(to: CGRect(x: hPadding, y: y, width: maxWidth * block.2, height: heights[index]))
                sungCopy.draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
                cg.restoreGState()
            }
            y += heights[index] + spacing
        }
    }

    // MARK: Title + watermark

    private func drawChrome() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 6

        let title = NSAttributedString(string: input.song.title, attributes: [
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
