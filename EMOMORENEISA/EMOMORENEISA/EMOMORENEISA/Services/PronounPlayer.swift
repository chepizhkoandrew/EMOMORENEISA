import AVFoundation

final class PronounPlayer {
    static let shared = PronounPlayer()

    private var player: AVAudioPlayer?

    private init() {}

    func play(pronoun: Pronoun) {
        let name: String
        switch pronoun {
        case .yo:       name = "pronoun_yo"
        case .tu:       name = "pronoun_tu"
        case .el:       name = "pronoun_el"
        case .nosotros: name = "pronoun_nosotros"
        case .vosotros: name = "pronoun_vosotros"
        case .ellos:    name = "pronoun_ellos"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
        } catch {}
    }
}
