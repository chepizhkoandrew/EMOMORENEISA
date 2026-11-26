import Foundation
import AVFoundation
import UIKit

/// What the user chose before dialing: a topic and/or a photo. Becomes the
/// baseline of the call (sent to the server for the system instruction, and
/// the photo goes into the opening turn).
struct LiveCallConfig: Identifiable {
    let id = UUID()
    var topic: String
    var photo: UIImage?
}

struct LiveLine: Identifiable, Equatable {
    enum Role { case user, tutor }
    let id = UUID()
    let role: Role
    var text: String
    var isOpen: Bool
}

/// Drives one Live Conversation call: billing, connection (and reconnects),
/// audio, and the rolling captions. Nothing is persisted — the transcript
/// lives only as long as this object.
@Observable
final class LiveCallModel {
    enum Phase: Equatable {
        case preparing, connecting, live, reconnecting
        case ended(EndReason)
    }
    enum EndReason: Equatable {
        case hungUp, outOfTreats, maxDuration, connectionLost, micDenied, interrupted, failed(String)
    }

    private(set) var phase: Phase = .preparing
    private(set) var lines: [LiveLine] = []
    private(set) var elapsed = 0
    private(set) var micLevel: Float = 0
    private(set) var tutorSpeaking = false
    private(set) var costPerMinute = 0
    var isMuted = false { didSet { audio.isMuted = isMuted } }

    private let config: LiveCallConfig
    private let audio = LiveAudioEngine()
    private var client: LiveSessionClient?
    private var start: ProxyClient.LiveStart?
    private var clockTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var openingSent = false
    private var interruptionObserver: NSObjectProtocol?

    init(config: LiveCallConfig) {
        self.config = config
    }

    var isEnded: Bool { if case .ended = phase { return true } else { return false } }

    // MARK: - Lifecycle

    func begin() async {
        guard phase == .preparing else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            finish(.micDenied); return
        }
        phase = .connecting

        let profile = AuthState.shared.profile
        do {
            let s = try await ProxyClient.shared.liveStart(
                topic: config.topic,
                hasPhoto: config.photo != nil,
                level: profile?.level ?? "A2",
                appLanguage: LocalizationManager.shared.language.rawValue,
                nativeLanguage: profile?.nativeLanguage ?? LocalizationManager.shared.language.rawValue,
                displayName: profile?.displayName,
                interests: profile.map { $0.hobbies.prefix(6).joined(separator: ", ") }
            )
            guard !isEnded else { return }
            start = s
            costPerMinute = s.costPerMinute
        } catch ProxyError.insufficientTreats {
            finish(.outOfTreats); return
        } catch {
            finish(.failed(error.localizedDescription)); return
        }

        wireAudio()
        do {
            try audio.start()
        } catch {
            finish(.failed(error.localizedDescription)); return
        }
        observeInterruptions()
        UIApplication.shared.isIdleTimerDisabled = true
        connect()
    }

    func hangUp() { finish(.hungUp) }

    /// Mid-call photo: the tutor reacts to it right away.
    func sendPhoto(_ image: UIImage) {
        guard phase == .live, let jpeg = Self.jpeg(image) else { return }
        audio.flush()
        client?.sendTurn(text: "(Te acabo de enviar una foto. Reacciona a ella y sigamos hablando.)", jpeg: jpeg)
    }

    private func finish(_ reason: EndReason) {
        guard !isEnded else { return }
        phase = .ended(reason)
        clockTask?.cancel()
        client?.onEvent = nil
        client?.close()
        client = nil
        audio.onMicChunk = nil
        audio.stop()
        tutorSpeaking = false
        micLevel = 0
        closeOpenLines()
        UIApplication.shared.isIdleTimerDisabled = false
        if let o = interruptionObserver { NotificationCenter.default.removeObserver(o) }
        // close() sends 1000 (normal closure): the relay ends the session and
        // stops billing immediately.
    }

    // MARK: - Connection

    private func connect() {
        guard let start else { return }
        audio.captureEnabled = false
        let c = LiveSessionClient()
        c.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event, from: c) }
        }
        client = c
        c.connect(wsURL: start.wsURL, sessionId: start.sessionId, ticket: start.ticket)
    }

    /// The phone's socket dropped (network blip). The relay keeps the Vertex
    /// session alive for ~45 s, so reattach to the same session.
    private func reconnect() {
        guard !isEnded else { return }
        guard reconnectAttempts < 4 else { finish(.connectionLost); return }
        reconnectAttempts += 1
        phase = .reconnecting
        audio.captureEnabled = false
        audio.flush()
        client?.onEvent = nil
        client?.close()
        client = nil
        let delay = UInt64(reconnectAttempts) * 800_000_000
        Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !self.isEnded else { return }
            self.connect()
        }
    }

    private func handle(_ event: LiveEvent, from source: LiveSessionClient) {
        guard source === client, !isEnded else { return }
        switch event {
        case .setupComplete:
            reconnectAttempts = 0
            phase = .live
            audio.captureEnabled = true
            startClockIfNeeded()
            if !openingSent {
                openingSent = true
                let jpeg = config.photo.flatMap { Self.jpeg($0) }
                source.sendTurn(text: "(La llamada acaba de empezar. Saluda y abre la conversación.)", jpeg: jpeg)
            }
        case .audio(let pcm):
            audio.enqueue(pcm16: pcm)
        case .inputTranscript(let t):
            append(t, role: .user)
        case .outputTranscript(let t):
            append(t, role: .tutor)
        case .interrupted:
            audio.flush()
            closeOpenLines(role: .tutor)
        case .turnComplete:
            closeOpenLines()
        case .balance(let b):
            WalletManager.shared.balanceTreats = b
        case .relayError(let err):
            switch err {
            case "insufficient_treats": finish(.outOfTreats)
            case "max_duration": finish(.maxDuration)
            default: finish(.failed(err))
            }
        case .closed(let code, let reason):
            print("[LIVE] closed: \(code) \(reason ?? "-")")
            // 4404 = the relay no longer knows this session (ended / expired).
            if code == 4404 || !openingSent {
                finish(openingSent ? .connectionLost : .failed(reason ?? "connection_closed"))
            } else {
                reconnect()
            }
        }
    }

    // MARK: - Call clock (display only — the relay bills per minute)

    private func startClockIfNeeded() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, !self.isEnded else { return }
                if self.phase == .live { self.elapsed += 1 }
            }
        }
    }

    // MARK: - Audio wiring

    private func wireAudio() {
        audio.onMicChunk = { [weak self] chunk in
            // Audio thread → main actor; the socket send itself is async.
            Task { @MainActor in self?.client?.sendAudio(chunk) }
        }
        audio.onMicLevel = { [weak self] level in
            Task { @MainActor in self?.micLevel = level }
        }
        audio.onPlaybackActiveChanged = { [weak self] active in
            Task { @MainActor in self?.tutorSpeaking = active }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.finish(.interrupted) }
        }
    }

    // MARK: - Captions

    private func append(_ chunk: String, role: LiveLine.Role) {
        if let i = lines.indices.last, lines[i].role == role, lines[i].isOpen {
            lines[i].text += chunk
        } else {
            closeOpenLines()
            lines.append(LiveLine(role: role, text: chunk.trimmingCharacters(in: .whitespaces), isOpen: true))
            if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        }
    }

    private func closeOpenLines(role: LiveLine.Role? = nil) {
        for i in lines.indices where lines[i].isOpen && (role == nil || lines[i].role == role) {
            lines[i].isOpen = false
        }
    }

    // MARK: - Helpers

    /// ≤768 px JPEG — plenty for the model, small enough for one WS frame.
    static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 768
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
