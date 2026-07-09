import Foundation
import Supabase
import Auth

// Single gateway to the Professor Madrid backend proxy. The proxy holds the
// OpenAI/Gemini keys server-side, verifies the Supabase JWT, and debits the
// treat wallet. The app never talks to OpenAI/Google directly anymore.
final class ProxyClient {
    static let shared = ProxyClient()
    private init() {}

    private var baseURL: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "ProxyBaseURL") as? String
        let v = (configured?.isEmpty == false) ? configured! : "https://api.professormadrid.com"
        return v.hasSuffix("/") ? String(v.dropLast()) : v
    }

    // MARK: - Public API

    func chat(
        systemPrompt: String,
        history: [LocalChatMessage],
        userText: String,
        imageData: [Data] = [],
        maxTokens: Int = 300
    ) async throws -> String {
        var body: [String: Any] = [
            "systemPrompt": systemPrompt,
            "history": history.map { ["isUser": $0.isUser, "text": $0.textContent ?? ""] },
            "userText": userText,
            "maxTokens": maxTokens
        ]
        if !imageData.isEmpty {
            body["imageData"] = imageData.map { $0.base64EncodedString() }
        }
        let json = try await postJSON(path: "/v1/chat", body: body)
        return (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // Background / utility completion. Not billed. `kind` = "enhance" | "summary" | "analyst".
    func utility(prompt: String, kind: String, maxTokens: Int = 256, temperature: Double = 0) async throws -> String {
        let json = try await postJSON(path: "/v1/utility", body: [
            "prompt": prompt, "kind": kind, "maxTokens": maxTokens, "temperature": temperature
        ])
        return (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // Returns raw decoded audio plus its MIME type. AAC is requested so the
    // server serves a compact, cache-backed file; PCM is wrapped into WAV by the
    // caller only when the server returns it (legacy/uncompressed fallback).
    func tts(text: String, context: String = "default") async throws -> (data: Data, mime: String) {
        let json = try await postJSON(path: "/v1/tts", body: ["text": text, "format": "aac", "context": context])
        guard let b64 = json["audioBase64"] as? String, let data = Data(base64Encoded: b64) else {
            throw ProxyError.decoding
        }
        let mime = (json["mime"] as? String) ?? "audio/pcm;rate=24000"
        return (data, mime)
    }

    // Speech-to-text via the proxy (OpenAI gpt-4o-transcribe server-side — most
    // accurate at catching Spanish word endings). Not separately billed; the
    // turn it belongs to carries the cost. Returns "" on silence/empty audio.
    func transcribe(audioData: Data, mime: String = "audio/mp4", language: String? = nil, prompt: String? = nil) async throws -> String {
        var body: [String: Any] = [
            "audioBase64": audioData.base64EncodedString(),
            "mime": mime
        ]
        if let language, !language.isEmpty { body["language"] = language }
        if let prompt, !prompt.isEmpty { body["prompt"] = prompt }
        let json = try await postJSON(path: "/v1/transcribe", body: body, timeout: 30)
        return (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    struct LoroResult {
        let spanish: String
        let english: String
        let sentence1: String
        let sentence2: String
        let segments: [(data: Data, mime: String)]
        let illustration: (data: Data, mime: String)?
    }

    func loro(prompt: String) async throws -> LoroResult {
        let json = try await postJSON(path: "/v1/loro", body: ["prompt": prompt, "format": "aac"], timeout: 90)
        let segs = (json["segments"] as? [[String: Any]] ?? []).compactMap { seg -> (Data, String)? in
            guard let b64 = seg["audioBase64"] as? String, let d = Data(base64Encoded: b64) else { return nil }
            return (d, (seg["mime"] as? String) ?? "audio/pcm;rate=24000")
        }
        var illustration: (data: Data, mime: String)? = nil
        if let b64 = json["illustrationBase64"] as? String, let d = Data(base64Encoded: b64) {
            illustration = (d, (json["illustrationMime"] as? String) ?? "image/jpeg")
        }
        return LoroResult(
            spanish: json["spanish"] as? String ?? "",
            english: json["english"] as? String ?? "",
            sentence1: json["sentence1"] as? String ?? "",
            sentence2: json["sentence2"] as? String ?? "",
            segments: segs,
            illustration: illustration
        )
    }

    // Streaming Loro: yields events as the server synthesizes each segment so the
    // UI can play segment 0 before the rest finish. Mirrors /v1/loro billing.
    enum LoroEvent {
        case meta(spanish: String, english: String, sentence1: String, sentence2: String, totalSegments: Int)
        case segment(index: Int, data: Data, mime: String)
        case illustration(data: Data, mime: String)
        case done(totalSeconds: Int)
    }

    func loroStream(prompt: String) -> AsyncThrowingStream<LoroEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await authToken()
                    guard let url = URL(string: baseURL + "/v1/loro/stream") else { throw ProxyError.badURL }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 120
                    req.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "format": "aac"])

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1

                    if status != 200 {
                        // Non-streaming error body (JSON). Drain and map like send().
                        var raw = Data()
                        for try await b in bytes { raw.append(b) }
                        let j = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
                        if status == 402 {
                            let balance = (j["balance"] as? NSNumber)?.intValue ?? 0
                            await MainActor.run { WalletManager.shared.handleInsufficientTreats(balance: balance) }
                            throw ProxyError.insufficientTreats(balance: balance)
                        }
                        if status == 401 { throw ProxyError.notSignedIn }
                        throw ProxyError.http(status: status, message: (j["error"] as? String) ?? "request_failed")
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                              let type = obj["type"] as? String else { continue }
                        switch type {
                        case "meta":
                            continuation.yield(.meta(
                                spanish: obj["spanish"] as? String ?? "",
                                english: obj["english"] as? String ?? "",
                                sentence1: obj["sentence1"] as? String ?? "",
                                sentence2: obj["sentence2"] as? String ?? "",
                                totalSegments: (obj["totalSegments"] as? NSNumber)?.intValue ?? 7
                            ))
                        case "segment":
                            if let idx = (obj["index"] as? NSNumber)?.intValue,
                               let b64 = obj["audioBase64"] as? String,
                               let d = Data(base64Encoded: b64) {
                                continuation.yield(.segment(index: idx, data: d, mime: (obj["mime"] as? String) ?? "audio/pcm;rate=24000"))
                            }
                        case "illustration":
                            if let b64 = obj["base64"] as? String, let d = Data(base64Encoded: b64) {
                                continuation.yield(.illustration(data: d, mime: (obj["mime"] as? String) ?? "image/jpeg"))
                            }
                        case "done":
                            continuation.yield(.done(totalSeconds: (obj["totalSeconds"] as? NSNumber)?.intValue ?? 0))
                        case "error":
                            throw ProxyError.http(status: 502, message: (obj["error"] as? String) ?? "loro_tts_failed")
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct WalletState {
        let balanceTreats: Int
        let hasPaid: Bool
        let trialGranted: Bool
    }

    func wallet() async throws -> WalletState { try walletState(from: await getJSON(path: "/v1/wallet")) }

    func bootstrap() async throws -> WalletState {
        try walletState(from: await postJSON(path: "/v1/bootstrap", body: [:]))
    }

    struct AnnotateResult {
        let annotations: [AnnotationItem]

        var annotationsJSON: String {
            let data = (try? JSONEncoder().encode(annotations)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    func annotate(imageData: [Data], objectList: String) async throws -> AnnotateResult {
        let body: [String: Any] = [
            "imageData": imageData.map { $0.base64EncodedString() },
            "objectList": objectList
        ]
        let json = try await postJSON(path: "/v1/annotate", body: body, timeout: 45)
        guard let rawAnnotations = json["annotations"] as? [[String: Any]] else {
            throw ProxyError.decoding
        }
        let annotations = rawAnnotations.compactMap { item -> AnnotationItem? in
            guard let label = item["label"] as? String,
                  let x = (item["x"] as? NSNumber)?.doubleValue,
                  let y = (item["y"] as? NSNumber)?.doubleValue else { return nil }
            let translation = (item["translation"] as? String) ?? ""
            return AnnotationItem(label: label, translation: translation, x: x, y: y)
        }
        return AnnotateResult(annotations: annotations)
    }

    func verbCheck(
        transcript: String,
        expected: String,
        infinitive: String,
        pronoun: String
    ) async throws -> Bool {
        let body: [String: Any] = [
            "transcript": transcript,
            "expected": expected,
            "infinitive": infinitive,
            "pronoun": pronoun
        ]
        let json = try await postJSON(path: "/v1/verb-check", body: body, timeout: 10)
        guard let correct = json["correct"] as? Bool else { throw ProxyError.decoding }
        return correct
    }

    // Sends a StoreKit 2 signed transaction (JWS) for server-side verification + crediting.
    func topup(signedTransaction: String) async throws -> WalletState {
        try walletState(from: await postJSON(path: "/v1/topup", body: ["signedTransaction": signedTransaction]))
    }

    struct CouponResult {
        let walletState: WalletState
        let creditedTreats: Int
    }

    func deleteAccount() async throws {
        _ = try await postJSON(path: "/v1/delete-account", body: [:])
    }

    func fetchIllustration(spanish: String, english: String) async -> (data: Data, mime: String)? {
        guard let json = try? await postJSON(
            path: "/v1/illustration",
            body: ["spanish": spanish, "english": english],
            timeout: 30
        ),
        let b64 = json["base64"] as? String,
        let data = Data(base64Encoded: b64) else { return nil }
        return (data, (json["mime"] as? String) ?? "image/jpeg")
    }

    // Redeems a coupon code. Throws ProxyError.http on invalid/expired/already-used codes.
    func redeemCoupon(code: String) async throws -> CouponResult {
        let json = try await postJSON(path: "/v1/coupon/redeem", body: ["code": code])
        let state = walletState(from: json)
        let credited = (json["creditedTreats"] as? NSNumber)?.intValue ?? 0
        return CouponResult(walletState: state, creditedTreats: credited)
    }

    // MARK: - Onboarding (utility class, not billed)

    struct OnboardingProbeResult {
        let nextQuestionText: String
        let targetSlot: String
        let reasoning: String
    }

    func onboardingProbe(
        pass: Int,
        pronoun: String,
        quizLanguage: String,
        transcripts: [String: String],
        previousProbe: [String: String]? = nil
    ) async throws -> OnboardingProbeResult {
        var body: [String: Any] = [
            "pass": pass,
            "pronoun": pronoun,
            "quizLanguage": quizLanguage,
            "transcripts": transcripts
        ]
        if let previousProbe { body["previousProbe"] = previousProbe }
        let json = try await postJSON(path: "/v1/onboarding/probe", body: body, timeout: 45)
        return OnboardingProbeResult(
            nextQuestionText: (json["nextQuestionText"] as? String) ?? "",
            targetSlot: (json["targetSlot"] as? String) ?? "",
            reasoning: (json["reasoning"] as? String) ?? ""
        )
    }

    struct OnboardingSynthesisResult {
        let tutorCheatSheet: String
        let narrativeSummary: String
        let aboutMeUserFacing: String
        let cityFlavor: String
        let extractedSlotsJSON: Data
        let version: Int
        let voiceTag: String
        let levelBreakdown: StudentLevelBreakdown?
    }

    func onboardingSynthesize(
        pronoun: String,
        quizLanguage: String,
        transcripts: [String: String],
        probes: [String: Any]?
    ) async throws -> OnboardingSynthesisResult {
        var body: [String: Any] = [
            "pronoun": pronoun,
            "quizLanguage": quizLanguage,
            "transcripts": transcripts
        ]
        if let probes { body["probes"] = probes }
        let json = try await postJSON(path: "/v1/onboarding/synthesize", body: body, timeout: 45)
        let slots = (json["extractedSlots"] as? [String: Any]) ?? [:]
        let slotsData = (try? JSONSerialization.data(withJSONObject: slots)) ?? Data("{}".utf8)

        var breakdown: StudentLevelBreakdown? = nil
        if let lb = json["levelBreakdown"] as? [String: Any] {
            func skill(_ key: String) -> SkillBand {
                let s = (lb[key] as? [String: Any]) ?? [:]
                return SkillBand(band: (s["band"] as? String) ?? "unknown",
                                 note: (s["note"] as? String) ?? "")
            }
            let goalsAny = (lb["goals"] as? [Any]) ?? []
            let goals = goalsAny.compactMap { $0 as? String }.filter { !$0.isEmpty }
            breakdown = StudentLevelBreakdown(
                overallBand: (lb["overallBand"] as? String) ?? "unknown",
                currentState: (lb["currentState"] as? String) ?? "",
                listening: skill("listening"),
                speaking: skill("speaking"),
                grammar: skill("grammar"),
                goals: goals
            )
        }

        return OnboardingSynthesisResult(
            tutorCheatSheet: (json["tutorCheatSheet"] as? String) ?? "",
            narrativeSummary: (json["narrativeSummary"] as? String) ?? "",
            aboutMeUserFacing: (json["aboutMeUserFacing"] as? String) ?? "",
            cityFlavor: (json["cityFlavor"] as? String) ?? "",
            extractedSlotsJSON: slotsData,
            version: (json["version"] as? NSNumber)?.intValue ?? 0,
            voiceTag: (json["voiceTag"] as? String) ?? "",
            levelBreakdown: breakdown
        )
    }

    func currentVoiceTag() async throws -> String {
        let json = try await getJSON(path: "/v1/voice/current")
        return (json["voiceTag"] as? String) ?? ""
    }

    private func walletState(from json: [String: Any]) -> WalletState {
        WalletState(
            balanceTreats: (json["balanceTreats"] as? NSNumber)?.intValue ?? 0,
            hasPaid: json["hasPaid"] as? Bool ?? false,
            trialGranted: json["trialGranted"] as? Bool ?? false
        )
    }

    // MARK: - Transport

    private func authToken() async throws -> String {
        do {
            let token = try await supabase.auth.session.accessToken
            if token.isEmpty { throw ProxyError.notSignedIn }
            return token
        } catch {
            throw ProxyError.notSignedIn
        }
    }

    private func getJSON(path: String, timeout: TimeInterval = 20) async throws -> [String: Any] {
        try await send(path: path, method: "GET", body: nil, timeout: timeout)
    }

    private func postJSON(path: String, body: [String: Any], timeout: TimeInterval = 30) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path: path, method: "POST", body: data, timeout: timeout)
    }

    private func send(path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> [String: Any] {
        let token = try await authToken()
        guard let url = URL(string: baseURL + path) else { throw ProxyError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        req.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] ?? [:]

        if status != 200 {
            let sentBody = body.flatMap { String(data: $0, encoding: .utf8) } ?? "<none>"
            print("[PROXY] \(method) \(path) → HTTP \(status) | resp: \(String(data: respData, encoding: .utf8)?.prefix(300) ?? "<binary>") | sent: \(sentBody.prefix(400))")
        }

        if status == 200 { return json }

        if status == 402 {
            let balance = (json["balance"] as? NSNumber)?.intValue ?? 0
            await MainActor.run { WalletManager.shared.handleInsufficientTreats(balance: balance) }
            throw ProxyError.insufficientTreats(balance: balance)
        }
        if status == 401 { throw ProxyError.notSignedIn }
        throw ProxyError.http(status: status, message: (json["error"] as? String) ?? "request_failed")
    }
}

enum ProxyError: LocalizedError {
    case notSignedIn
    case insufficientTreats(balance: Int)
    case http(status: Int, message: String)
    case badURL
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Please sign in to continue."
        case .insufficientTreats: return "You're out of treats. Top up to keep going."
        case .http(let code, _): return "Server error \(code). Please try again."
        case .badURL: return "Invalid server address."
        case .decoding: return "Could not read the server response."
        }
    }
}
