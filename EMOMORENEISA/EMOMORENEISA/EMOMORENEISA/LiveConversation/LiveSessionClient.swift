import Foundation

/// Events parsed from Gemini Live `BidiGenerateContentServerMessage`s.
enum LiveEvent {
    case setupComplete
    case audio(Data)                 // 24 kHz PCM16 mono
    case inputTranscript(String)     // what the user said (chunk)
    case outputTranscript(String)    // what the tutor said (chunk)
    case interrupted                 // user barged in: drop queued audio
    case turnComplete
    case balance(Int)                // relay billed another minute
    case relayError(String)          // insufficient_treats | max_duration | connection_failed | …
    case closed(code: Int, reason: String?)
}

/// The phone's WebSocket to our Live relay (/v1/live/ws), which forwards to
/// Gemini Live on Vertex AI. The relay sends the `setup`, bills per minute and
/// hides Google's ~10-minute reconnects; this side only streams audio/turns
/// and reads Gemini's server messages plus `{"relay": …}` control messages.
nonisolated final class LiveSessionClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    var onEvent: ((LiveEvent) -> Void)?

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var closed = false
    private var closeReason: String?
    private var closeCode = -1

    func connect(wsURL: String, sessionId: String, ticket: String) {
        var comps = URLComponents(string: wsURL)
        comps?.queryItems = [URLQueryItem(name: "session", value: sessionId), URLQueryItem(name: "ticket", value: ticket)]
        guard let url = comps?.url else {
            emitClosed(code: -1, "bad_url")
            return
        }
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        task.resume()
        receiveLoop()
    }

    func close() {
        lock.lock(); let already = closed; closed = true; lock.unlock()
        guard !already else { return }
        task?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    // MARK: - Client messages

    func sendAudio(_ pcm16: Data) {
        sendJSON(["realtimeInput": ["audio": ["mimeType": "audio/pcm;rate=16000", "data": pcm16.base64EncodedString()]]])
    }

    /// A complete user turn (text and/or a JPEG). Interrupts the tutor if it
    /// is mid-sentence — fine, these are explicit user actions.
    func sendTurn(text: String, jpeg: Data? = nil) {
        var parts: [[String: Any]] = []
        if let jpeg {
            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        parts.append(["text": text])
        sendJSON(["clientContent": ["turns": [["role": "user", "parts": parts]], "turnComplete": true]])
    }

    /// Diagnostics for the relay's log (never forwarded to Google).
    func sendLog(_ info: [String: Any]) {
        sendJSON(["clientLog": info])
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if let error { self?.emitClosed(code: -1, error.localizedDescription) }
        }
    }

    // MARK: - Server messages

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.emitClosed(code: self.closeCode, self.closeReason ?? error.localizedDescription)
            case .success(let message):
                let data: Data?
                switch message {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8)
                @unknown default: data = nil
                }
                if let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    self.handle(json)
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ json: [String: Any]) {
        if json["setupComplete"] != nil { onEvent?(.setupComplete) }

        if let sc = json["serverContent"] as? [String: Any] {
            if let turn = sc["modelTurn"] as? [String: Any], let parts = turn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inline = part["inlineData"] as? [String: Any],
                       let b64 = inline["data"] as? String,
                       let audio = Data(base64Encoded: b64) {
                        onEvent?(.audio(audio))
                    }
                }
            }
            if let t = (sc["inputTranscription"] as? [String: Any])?["text"] as? String, !t.isEmpty {
                onEvent?(.inputTranscript(t))
            }
            if let t = (sc["outputTranscription"] as? [String: Any])?["text"] as? String, !t.isEmpty {
                onEvent?(.outputTranscript(t))
            }
            if (sc["interrupted"] as? Bool) == true { onEvent?(.interrupted) }
            if (sc["turnComplete"] as? Bool) == true { onEvent?(.turnComplete) }
        }

        if let relay = json["relay"] as? [String: Any] {
            if let err = relay["error"] as? String { onEvent?(.relayError(err)) }
            if let bal = (relay["balance"] as? NSNumber)?.intValue { onEvent?(.balance(bal)) }
        }
    }

    private func emitClosed(code: Int, _ reason: String?) {
        lock.lock(); let already = closed; closed = true; lock.unlock()
        guard !already else { return }
        onEvent?(.closed(code: code, reason: reason))
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.closeCode = closeCode.rawValue
        closeReason = text
        print("[LIVE] socket closed: \(closeCode.rawValue) \(text)")
        emitClosed(code: closeCode.rawValue, text)
    }
}
