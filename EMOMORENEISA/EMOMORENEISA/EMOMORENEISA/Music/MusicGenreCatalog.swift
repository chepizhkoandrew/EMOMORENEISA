import Foundation

struct MusicGenre: Identifiable, Hashable {
    /// English name — shown in UI (via `L`) and sent verbatim to the model as a style tag.
    let name: String
    let category: String
    var id: String { name }
}

/// The full searchable genre catalog. Names double as model style tags, so they
/// stay in English regardless of UI language (music models are trained on
/// English tags). Featured = the quick-pick chips on the setup screen.
enum MusicGenreCatalog {

    static let featured: [String] = [
        "Reggaetón", "Latin Pop", "Bachata", "Cumbia",
        "Pop", "Hip-Hop", "Rock", "Lo-fi Chill"
    ]

    static let all: [MusicGenre] = {
        var list: [MusicGenre] = []
        func add(_ category: String, _ names: [String]) {
            list.append(contentsOf: names.map { MusicGenre(name: $0, category: category) })
        }

        add("Latin & Spanish", [
            "Reggaetón", "Latin Pop", "Bachata", "Cumbia", "Salsa", "Merengue",
            "Flamenco", "Flamenco Pop", "Rumba Flamenca", "Sevillanas",
            "Latin Trap", "Dembow", "Perreo", "Neoperreo", "Urbano",
            "Corridos Tumbados", "Regional Mexicano", "Mariachi", "Ranchera",
            "Banda", "Norteño", "Tejano", "Vallenato", "Bolero", "Son Cubano",
            "Timba", "Bossa Nova", "Samba", "Brazilian Funk", "Forró",
            "Tango", "Milonga", "Andean Folk", "Latin Jazz", "Boogaloo",
            "Cha-Cha-Chá", "Mambo", "Cumbia Villera", "Chicha", "Latin Rock",
            "Rock en Español", "Spanish Indie", "Copla", "Zarzuela"
        ])

        add("Pop", [
            "Pop", "Dance Pop", "Synth-pop", "Electropop", "Dream Pop",
            "Indie Pop", "Art Pop", "Baroque Pop", "Bubblegum Pop", "Power Pop",
            "Teen Pop", "K-Pop", "J-Pop", "City Pop", "Europop", "Hyperpop",
            "Bedroom Pop", "Chamber Pop", "Sophisti-pop", "Sunshine Pop",
            "Jangle Pop", "Twee Pop", "PC Music", "Y2K Pop"
        ])

        add("Rock", [
            "Rock", "Classic Rock", "Hard Rock", "Soft Rock", "Indie Rock",
            "Alternative Rock", "Garage Rock", "Psychedelic Rock", "Prog Rock",
            "Post-Rock", "Math Rock", "Surf Rock", "Rockabilly", "Glam Rock",
            "Grunge", "Post-Grunge", "Britpop", "Shoegaze", "Noise Rock",
            "Stoner Rock", "Desert Rock", "Southern Rock", "Blues Rock",
            "Folk Rock", "Space Rock", "Krautrock", "Arena Rock", "Yacht Rock"
        ])

        add("Metal & Heavy", [
            "Heavy Metal", "Thrash Metal", "Death Metal", "Black Metal",
            "Doom Metal", "Sludge Metal", "Power Metal", "Symphonic Metal",
            "Folk Metal", "Viking Metal", "Progressive Metal", "Djent",
            "Metalcore", "Deathcore", "Nu Metal", "Industrial Metal",
            "Gothic Metal", "Speed Metal", "Groove Metal"
        ])

        add("Punk & Hardcore", [
            "Punk Rock", "Pop Punk", "Ska Punk", "Post-Punk", "Proto-Punk",
            "Hardcore Punk", "Post-Hardcore", "Emo", "Emo Pop", "Screamo",
            "Crust Punk", "Anarcho-Punk", "Oi!", "Riot Grrrl", "Folk Punk",
            "Cowpunk", "Psychobilly", "Garage Punk", "Egg Punk", "Dance-Punk"
        ])

        add("Hip-Hop & Rap", [
            "Hip-Hop", "Boom Bap", "Trap", "Drill", "UK Drill", "Grime",
            "Cloud Rap", "Mumble Rap", "Conscious Hip-Hop", "Jazz Rap",
            "Lo-fi Hip-Hop", "Old School Hip-Hop", "G-Funk", "Crunk",
            "Hyphy", "Phonk", "Drift Phonk", "Horrorcore", "Chopped and Screwed",
            "Abstract Hip-Hop", "Rage Rap", "Plugg", "Jerk Rap", "Miami Bass"
        ])

        add("R&B & Soul", [
            "R&B", "Contemporary R&B", "Alternative R&B", "Neo Soul", "Soul",
            "Northern Soul", "Southern Soul", "Motown", "Funk", "P-Funk",
            "Disco", "Nu-Disco", "Boogie", "Quiet Storm", "New Jack Swing",
            "Doo-Wop", "Gospel", "Slow Jam"
        ])

        add("Electronic & Dance", [
            "EDM", "House", "Deep House", "Tech House", "Progressive House",
            "Tropical House", "Future House", "Bass House", "Amapiano",
            "Afro House", "Techno", "Melodic Techno", "Minimal Techno",
            "Acid Techno", "Industrial Techno", "Trance", "Psytrance",
            "Goa Trance", "Hardstyle", "Gabber", "Happy Hardcore", "UK Garage",
            "2-Step", "Speed Garage", "Dubstep", "Riddim", "Brostep",
            "Drum and Bass", "Liquid DnB", "Jungle", "Breakbeat", "Big Beat",
            "Electro", "Electroclash", "Future Bass", "Kawaii Future Bass",
            "Moombahton", "Baile Funk", "Jersey Club", "Footwork", "Eurodance",
            "Hands Up", "Italo Disco", "French House", "Complextro", "Midtempo"
        ])

        add("Chill & Atmospheric", [
            "Lo-fi Chill", "Chillhop", "Chillwave", "Ambient", "Dark Ambient",
            "Space Ambient", "Downtempo", "Trip-Hop", "Chillout", "Psybient",
            "New Age", "Meditation", "Binaural Beats", "Slowcore", "Sadcore",
            "Muzak", "Elevator Music", "Sleep Music", "Rainy Day Jazz"
        ])

        add("Retro & Internet Culture", [
            "Vaporwave", "Future Funk", "Mallsoft", "Synthwave", "Retrowave",
            "Darksynth", "Outrun", "Chiptune", "8-bit", "Bitpop", "Nintendocore",
            "Witch House", "Seapunk", "Webcore", "Breakcore", "Dariacore",
            "Nightcore", "Sped Up", "Slowed and Reverb", "Weirdcore",
            "Dungeon Synth", "Sovietwave", "Frutiger Aero", "Y2K Rave"
        ])

        add("Jazz", [
            "Jazz", "Smooth Jazz", "Bebop", "Cool Jazz", "Hard Bop",
            "Free Jazz", "Modal Jazz", "Swing", "Big Band", "Gypsy Jazz",
            "Dixieland", "Fusion", "Acid Jazz", "Nu Jazz", "Vocal Jazz",
            "Ragtime", "Lounge", "Bossa Jazz", "Spiritual Jazz"
        ])

        add("Blues & Country", [
            "Blues", "Delta Blues", "Chicago Blues", "Electric Blues",
            "Country Blues", "Country", "Classic Country", "Outlaw Country",
            "Country Pop", "Bluegrass", "Honky Tonk", "Americana",
            "Alt-Country", "Western Swing", "Gothic Country", "Red Dirt",
            "Zydeco", "Cajun"
        ])

        add("Folk & World", [
            "Folk", "Indie Folk", "Freak Folk", "Chamber Folk", "Anti-Folk",
            "Celtic", "Irish Folk", "Sea Shanty", "Klezmer", "Balkan Brass",
            "Gypsy Folk", "Fado", "Chanson", "Schlager", "Polka",
            "Ukrainian Folk", "Slavic Folk", "Nordic Folk", "Medieval Folk",
            "Afrobeat", "Afrobeats", "Highlife", "Soukous", "Desert Blues",
            "Ethio-Jazz", "Reggae", "Roots Reggae", "Dub", "Dancehall",
            "Ska", "Rocksteady", "Soca", "Calypso", "Zouk", "Kompa",
            "Bollywood", "Bhangra", "Qawwali", "Arabic Pop", "Raï",
            "Turkish Psych", "Anatolian Rock", "K-Indie", "Mandopop",
            "Cantopop", "Enka", "Gamelan", "Throat Singing", "Hawaiian",
            "Flamenco Fusion"
        ])

        add("Classical & Cinematic", [
            "Classical", "Baroque", "Romantic Era", "Opera", "Choral",
            "String Quartet", "Piano Solo", "Minimalism", "Neoclassical",
            "Contemporary Classical", "Film Score", "Epic Orchestral",
            "Trailer Music", "Video Game Music", "Anime Soundtrack",
            "Spaghetti Western", "Waltz", "March", "Lullaby"
        ])

        add("Fun & Special", [
            "Kids Song", "Nursery Rhyme", "Educational Song", "Campfire Song",
            "Birthday Song", "Christmas", "Villancicos", "Halloween",
            "Circus Music", "Polka Party", "Oompah", "Barbershop Quartet",
            "A Cappella", "Beatbox", "Whistling", "Kazoo Novelty",
            "Meme Song", "Parody Song", "Musical Theatre", "Disney Style",
            "Jingle", "Sports Anthem", "Stadium Chant", "Tarantella"
        ])

        return list
    }()

    static var categories: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    static func genres(in category: String) -> [MusicGenre] {
        all.filter { $0.category == category }
    }

    /// Name-only — matching on `category` too used to mean searching
    /// "hardcore" pulled in every genre under "Punk & Hardcore" (Ska Punk,
    /// Emo, Post-Punk...), not just genres actually named for it.
    static func search(_ query: String) -> [MusicGenre] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}

/// Song length options. Treat costs are placeholders until real GPU cost per
/// length is measured (mirrors server `config.actionCosts.music*`).
enum SongLength: Int, CaseIterable, Identifiable {
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var treatCost: Int {
        switch self {
        case .seconds30: return 15
        case .minute1: return 25
        case .minutes2: return 45
        }
    }

    var titleKey: String {
        switch self {
        case .seconds30: return "30 seconds"
        case .minute1: return "1 minute"
        case .minutes2: return "2 minutes"
        }
    }

    var subtitleKey: String {
        switch self {
        case .seconds30: return "a quick hook"
        case .minute1: return "verse and chorus"
        case .minutes2: return "a full little song"
        }
    }
}
