import Foundation
import AVFoundation

@Observable
final class ParrotService {
    enum State {
        case idle
        case generating(progress: Double, label: String)
        case ready
        case failed(String)
    }

    var state: State = .idle

    // The script (one LLM call) and all 7 TTS segments are produced server-side by
    // the proxy and billed as a single "loro" action. No API keys live in the app.
    func generate(phrase: ParrotPhrase, level: String) async {
        await MainActor.run { state = .generating(progress: 0.05, label: "Asking Seagull Steven...") }

        do {
            let prompt = PromptBuilder.parrotScriptPrompt(
                phrase: phrase.selectedWords.joined(separator: " "),
                level: level
            )
            await MainActor.run { state = .generating(progress: 0.15, label: "Recording…") }

            let result = try await ProxyClient.shared.loro(prompt: prompt)
            phrase.spanishPhrase = result.spanish
            phrase.englishTranslation = result.english

            guard !result.segments.isEmpty else {
                throw NSError(domain: "Parrot", code: 5, userInfo: [NSLocalizedDescriptionKey: "No audio returned"])
            }

            var paths: [String] = []
            let dir = ParrotPhrase.parrotDir(for: phrase.id)
            for (i, seg) in result.segments.enumerated() {
                let (data, ext) = decodeSegment(seg.data, mimeType: seg.mime)
                let fileURL = dir.appendingPathComponent("\(i + 1).\(ext)")
                try data.write(to: fileURL)
                paths.append("esp-parrot/\(phrase.id.uuidString)/\(i + 1).\(ext)")
                let prog = 0.2 + (Double(i) / Double(result.segments.count)) * 0.75
                await MainActor.run {
                    state = .generating(progress: prog, label: "Saving segment \(i + 1) of \(result.segments.count)…")
                }
            }

            phrase.segmentPaths = paths

            if let illo = result.illustration {
                let ext = illustrationExt(for: illo.mime)
                let fileURL = dir.appendingPathComponent("illustration.\(ext)")
                if (try? illo.data.write(to: fileURL, options: .atomic)) != nil {
                    let relPath = "esp-parrot/\(phrase.id.uuidString)/illustration.\(ext)"
                    await MainActor.run { phrase.illustrationPath = relPath }
                }
            }

            await MainActor.run { state = .ready }
        } catch let e as ProxyError {
            await MainActor.run {
                if case .insufficientTreats = e {
                    state = .failed("You're out of treats. Top up to keep practicing.")
                } else {
                    state = .failed(e.localizedDescription)
                }
            }
        } catch {
            await MainActor.run { state = .failed(error.localizedDescription) }
        }
    }

    // Streaming generate: writes each segment WAV to disk as it arrives so the
    // player can begin on segment 1 (~2-3s) instead of waiting for all 7. The
    // billing is identical to generate() — one flat "loro" action server-side.
    // `onFirstSegment` fires once the first playable segment (index 0) is on disk.
    func generateStreaming(phrase: ParrotPhrase, level: String, onFirstSegment: @escaping () -> Void) async {
        AnalyticsService.shared.track(.parrotSessionStarted)
        await MainActor.run { state = .generating(progress: 0.05, label: "Asking Seagull Steven...") }

        let dir = ParrotPhrase.parrotDir(for: phrase.id)
        // Start clean so stale segments from a previous attempt can't be played.
        if let existing = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in existing where ["wav", "aac", "m4a", "jpg", "jpeg", "png"].contains(f.pathExtension) {
                try? FileManager.default.removeItem(at: f)
            }
        }

        var expected = 7
        var segExt = "wav"
        var written = Set<Int>()
        var firstFired = false

        do {
            let prompt = PromptBuilder.parrotScriptPrompt(
                phrase: phrase.selectedWords.joined(separator: " "),
                level: level
            )

            for try await event in ProxyClient.shared.loroStream(prompt: prompt) {
                switch event {
                case let .meta(spanish, english, _, _, total):
                    expected = total
                    await MainActor.run {
                        phrase.spanishPhrase = spanish
                        phrase.englishTranslation = english
                        state = .generating(progress: 0.15, label: "Recording…")
                    }

                case let .segment(index, data, mime):
                    let (out, ext) = decodeSegment(data, mimeType: mime)
                    segExt = ext
                    let fileURL = dir.appendingPathComponent("\(index + 1).\(ext)")
                    try? out.write(to: fileURL, options: .atomic)
                    written.insert(index)
                    let prog = 0.2 + (Double(written.count) / Double(max(1, expected))) * 0.75
                    await MainActor.run {
                        state = .generating(progress: prog, label: "Saving segment \(written.count) of \(expected)…")
                    }
                    if index == 0 && !firstFired {
                        firstFired = true
                        await MainActor.run {
                            state = .ready
                            onFirstSegment()
                        }
                    }

                case let .illustration(data, mime):
                    let ext = illustrationExt(for: mime)
                    let fileURL = dir.appendingPathComponent("illustration.\(ext)")
                    if (try? data.write(to: fileURL, options: .atomic)) != nil {
                        let relPath = "esp-parrot/\(phrase.id.uuidString)/illustration.\(ext)"
                        await MainActor.run { phrase.illustrationPath = relPath }
                    }

                case .done:
                    let paths = (0..<expected).map { "esp-parrot/\(phrase.id.uuidString)/\($0 + 1).\(segExt)" }
                    await MainActor.run {
                        phrase.segmentPaths = paths
                        if !firstFired { firstFired = true; state = .ready; onFirstSegment() }
                    }
                }
            }
        } catch let e as ProxyError {
            await MainActor.run {
                if case .insufficientTreats = e {
                    state = .failed("You're out of treats. Top up to keep practicing.")
                } else {
                    state = .failed(e.localizedDescription)
                }
            }
        } catch {
            await MainActor.run { state = .failed(error.localizedDescription) }
        }
    }

    // Retroactively fetches and saves the illustration for memory cards that were
    // created before the illustration system was deployed. The image is stored in
    // the source parrot phrase's directory so it shares the same on-disk location.
    // No-ops when already set. Best-effort: never throws, never changes state.
    func ensureIllustration(for card: MemoryCard) async {
        guard card.illustrationPath == nil else { return }
        guard !card.content.isEmpty else { return }
        guard let illo = await ProxyClient.shared.fetchIllustration(
            spanish: card.content,
            english: card.translation
        ) else { return }
        let ext = illustrationExt(for: illo.mime)
        let dirId = card.sourceParrotId ?? card.id
        let dir = ParrotPhrase.parrotDir(for: dirId)
        let fileURL = dir.appendingPathComponent("illustration.\(ext)")
        if (try? illo.data.write(to: fileURL, options: .atomic)) != nil {
            let relPath = "esp-parrot/\(dirId.uuidString)/illustration.\(ext)"
            await MainActor.run { card.illustrationPath = relPath }
        }
    }

    // Retroactively fetches and saves the illustration for phrases that were
    // generated before the illustration system was deployed (illustrationPath == nil).
    // No-ops when already set. Best-effort: never throws, never changes state.
    func ensureIllustration(for phrase: ParrotPhrase) async {
        guard phrase.illustrationPath == nil else { return }
        guard !phrase.spanishPhrase.isEmpty else { return }
        guard let illo = await ProxyClient.shared.fetchIllustration(
            spanish: phrase.spanishPhrase,
            english: phrase.englishTranslation
        ) else { return }
        let ext = illustrationExt(for: illo.mime)
        let dir = ParrotPhrase.parrotDir(for: phrase.id)
        let fileURL = dir.appendingPathComponent("illustration.\(ext)")
        if (try? illo.data.write(to: fileURL, options: .atomic)) != nil {
            let relPath = "esp-parrot/\(phrase.id.uuidString)/illustration.\(ext)"
            await MainActor.run { phrase.illustrationPath = relPath }
        }
    }

    // MARK: - Decode

    // Maps a server audio buffer to (playable bytes, file extension). AAC is
    // played natively by AVAudioPlayer, so it is written as-is; only raw PCM needs
    // the WAV header. Extension is preserved so the player loads the right format.
    private func decodeSegment(_ rawData: Data, mimeType: String) -> (data: Data, ext: String) {
        let m = mimeType.lowercased()
        if m.hasPrefix("audio/aac") { return (rawData, "aac") }
        if m.hasPrefix("audio/mp4") || m.hasPrefix("audio/m4a") || m.hasPrefix("audio/x-m4a") { return (rawData, "m4a") }
        if m.hasPrefix("audio/wav") || m.hasPrefix("audio/wave") { return (rawData, "wav") }
        return (audioDataToWAV(rawData, mimeType: mimeType), "wav")
    }

    // Maps an illustration MIME type to a file extension. Defaults to jpg since
    // the server transcodes to JPEG; png is preserved for the transcode-fallback.
    private func illustrationExt(for mime: String) -> String {
        let m = mime.lowercased()
        if m.contains("png") { return "png" }
        return "jpg"
    }

    // MARK: - PCM → WAV

    private func audioDataToWAV(_ rawData: Data, mimeType: String) -> Data {
        if mimeType.hasPrefix("audio/wav") || mimeType.hasPrefix("audio/wave") { return rawData }
        let sampleRate: UInt32
        if let rateStr = mimeType.components(separatedBy: "rate=").last?.trimmingCharacters(in: .whitespaces),
           let rate = UInt32(rateStr) {
            sampleRate = rate
        } else {
            sampleRate = 24000
        }
        return wrapPCMInWAV(pcmData: rawData, sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
    }

    private func wrapPCMInWAV(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let dataSize = UInt32(pcmData.count)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        var h = Data()
        func u32(_ v: UInt32) { h.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        func u16(_ v: UInt16) { h.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        h.append(contentsOf: "RIFF".utf8); u32(36 + dataSize)
        h.append(contentsOf: "WAVE".utf8)
        h.append(contentsOf: "fmt ".utf8); u32(16)
        u16(1); u16(channels); u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bitsPerSample)
        h.append(contentsOf: "data".utf8); u32(dataSize)
        return h + pcmData
    }
}
