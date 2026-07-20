import Foundation

// Curated pickers for the Roleplay podcast setup flow (object/guest,
// environment, topic), plus the rotating TTS voice roster for the object.
enum RoleplayContent {

    // Guests with built-in charisma: historical figures, mythological gods,
    // folklore/literary characters, and personified concepts — all public
    // domain, all with an established voice, quirks, and story the model can
    // actually play, rather than a personality invented from scratch for a
    // household object.
    static let objects: [String] = [
        "Cleopatra, the last pharaoh of Egypt",
        "Leonardo da Vinci, Renaissance genius",
        "Sherlock Holmes, the legendary detective",
        "Dracula, the ancient vampire count",
        "Don Quixote, the deluded knight-errant",
        "Zeus, king of the Greek gods",
        "Anubis, the Egyptian god of the afterlife",
        "an ancient dragon guarding a mountain of gold",
        "a mischievous trickster fox spirit",
        "a fortune teller who claims to see everything",
        "a ghost haunting an old castle",
        "a legendary pirate captain",
        "Mother Nature herself",
        "Father Time, keeper of every clock",
        "a genie freshly freed from the lamp",
        "the Sphinx, who speaks only in riddles"
    ]

    static let environments: [String] = [
        "a cozy café in Madrid",
        "a rooftop terrace at sunset",
        "a busy street market",
        "a quiet library",
        "a beach at sunrise",
        "a mountain cabin",
        "a radio studio",
        "a city park bench",
        "a kitchen at midnight",
        "a train station platform"
    ]

    static let topics: [String] = [
        "childhood memories",
        "travel dreams",
        "daily routines",
        "food & cooking",
        "music & dancing",
        "weekend plans",
        "family traditions",
        "hopes for the future",
        "funny mishaps",
        "life advice"
    ]

    // Chirp3-HD voices distinct from Madrid's default (es-ES-Chirp3-HD-Achird).
    // MUST use the full "{locale}-Chirp3-HD-{Name}" form — Google Cloud TTS
    // rejects a bare name like "Charon" with "This voice requires a model
    // name to be specified" (verified directly against the API), which was
    // silently forcing every object line through the flaky Gemini-preview/
    // OpenAI fallback tiers instead of the reliable primary one Madrid uses.
    // Kore is the only one of these confirmed female in Google's voice docs —
    // Charon/Puck/Fenrir are male. Split into gendered pools so a female-coded
    // guest never gets hash-assigned a man's voice (see femaleVoices below).
    static let objectVoices: [String] = [
        "es-ES-Chirp3-HD-Charon", "es-ES-Chirp3-HD-Kore", "es-ES-Chirp3-HD-Puck", "es-ES-Chirp3-HD-Fenrir"
    ]
    private static let femaleVoices: [String] = ["es-ES-Chirp3-HD-Kore"]
    private static let maleVoices: [String] = ["es-ES-Chirp3-HD-Charon", "es-ES-Chirp3-HD-Puck", "es-ES-Chirp3-HD-Fenrir"]

    /// Explicit gender for every entry in `objects` — a fixed, curated list,
    /// so these are hand-assigned rather than guessed from keywords. Custom
    /// guest names (typed in, not picked from this list) fall through to the
    /// keyword heuristic in `voiceForObject` below.
    private static let curatedGender: [String: Bool] = [ // true = female
        "cleopatra, the last pharaoh of egypt": true,
        "leonardo da vinci, renaissance genius": false,
        "sherlock holmes, the legendary detective": false,
        "dracula, the ancient vampire count": false,
        "don quixote, the deluded knight-errant": false,
        "zeus, king of the greek gods": false,
        "anubis, the egyptian god of the afterlife": false,
        "mother nature herself": true,
        "father time, keeper of every clock": false,
        "the sphinx, who speaks only in riddles": true
    ]

    private static let femaleKeywords: Set<String> = [
        "she", "her", "herself", "queen", "goddess", "princess", "empress",
        "lady", "mother", "sister", "aunt", "girl", "woman", "witch",
        "duchess", "actress", "priestess", "sorceress", "queen's", "mrs", "miss", "ms"
    ]
    private static let maleKeywords: Set<String> = [
        "he", "him", "himself", "king", "prince", "emperor", "lord", "father",
        "brother", "uncle", "boy", "man", "monk", "priest", "duke", "actor",
        "husband", "mr", "sir", "god"
    ]

    /// Deterministic pick so the same object always gets the same voice across
    /// sessions, instead of a fresh random assignment each time. Gender-aware:
    /// checks the curated list first, then a lightweight keyword heuristic for
    /// custom guest names, falling back to the full mixed pool when neither
    /// signals a gender (kept correct over clever — an unmatched neutral
    /// character just gets any consistent voice, not a wrong one).
    static func voiceForObject(_ label: String) -> String {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return objectVoices[0] }

        let pool: [String]
        if let isFemale = curatedGender[normalized] {
            pool = isFemale ? femaleVoices : maleVoices
        } else {
            let words = Set(normalized.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: femaleKeywords) {
                pool = femaleVoices
            } else if !words.isDisjoint(with: maleKeywords) {
                pool = maleVoices
            } else {
                pool = objectVoices
            }
        }

        var hash: UInt64 = 5381
        for byte in normalized.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(pool.count))
        return pool[index]
    }
}
