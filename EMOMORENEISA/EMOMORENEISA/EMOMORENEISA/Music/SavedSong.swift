import Foundation
import SwiftData

/// A generated song saved on-device so it lands in "My Songs" (the music
/// counterpart of `LocalChatSession`). The mp3 lives on disk under
/// Documents/music-songs/<id>.mp3; the karaoke timings and picture plan are
/// stored as encoded JSON so a saved song replays karaoke exactly like a fresh
/// one.
@Model
final class SavedSong {
    @Attribute(.unique) var id: UUID
    var title: String
    var genre: String
    var durationSec: Int
    var lyrics: String
    /// Relative path (under Documents) to the saved mp3.
    var audioPath: String
    var linesJSON: Data
    var scenesJSON: Data
    var createdAt: Date
    /// Set only on songs received from a friend ("Shared by X" tag in lists).
    /// Optional with nil defaults so existing rows survive as a lightweight
    /// SwiftData migration.
    var sharedByName: String?
    var sharedFromUserId: String?
    /// The song_shares row this song materialized from; guards re-downloads.
    var shareId: String?
    /// The memory-queue words the user picked when generating — the source of
    /// truth for lyric highlighting (scene words alone miss picked words the
    /// storyboard didn't give a scene to). Optional for lightweight migration.
    var pickedWordsJSON: Data?

    init(
        id: UUID = UUID(),
        title: String,
        genre: String,
        durationSec: Int,
        lyrics: String,
        audioPath: String,
        linesJSON: Data,
        scenesJSON: Data,
        createdAt: Date = Date(),
        sharedByName: String? = nil,
        sharedFromUserId: String? = nil,
        shareId: String? = nil,
        pickedWordsJSON: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.genre = genre
        self.durationSec = durationSec
        self.lyrics = lyrics
        self.audioPath = audioPath
        self.linesJSON = linesJSON
        self.scenesJSON = scenesJSON
        self.createdAt = createdAt
        self.sharedByName = sharedByName
        self.sharedFromUserId = sharedFromUserId
        self.shareId = shareId
        self.pickedWordsJSON = pickedWordsJSON
    }

    var pickedWords: [String] {
        guard let pickedWordsJSON else { return [] }
        return (try? JSONDecoder().decode([String].self, from: pickedWordsJSON)) ?? []
    }

    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var audioURL: URL { Self.docs.appendingPathComponent(audioPath) }

    /// Writes the audio to disk and inserts the record. Best-effort: a save
    /// failure must never break the just-finished generation flow, so it
    /// returns nil instead of throwing.
    @discardableResult
    @MainActor
    static func persist(
        _ song: ProxyClient.MusicSong,
        in context: ModelContext,
        sharedByName: String? = nil,
        sharedFromUserId: String? = nil,
        shareId: String? = nil,
        pickedWords: [String] = []
    ) -> SavedSong? {
        // A shared song already materialized on this device: return it as-is
        // instead of writing a duplicate copy.
        if let shareId {
            let existing = try? context.fetch(
                FetchDescriptor<SavedSong>(predicate: #Predicate { $0.shareId == shareId })
            ).first
            if let existing { return existing }
        }

        let id = UUID()
        let relPath = "music-songs/\(id.uuidString).mp3"
        let fileURL = docs.appendingPathComponent(relPath)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try song.audioData.write(to: fileURL)
            let saved = SavedSong(
                id: id,
                title: song.title.isEmpty ? song.genre : song.title,
                genre: song.genre,
                durationSec: song.durationSec,
                lyrics: song.lyrics,
                audioPath: relPath,
                linesJSON: (try? JSONEncoder().encode(song.lines)) ?? Data(),
                scenesJSON: (try? JSONEncoder().encode(song.scenes)) ?? Data(),
                sharedByName: sharedByName,
                sharedFromUserId: sharedFromUserId,
                shareId: shareId,
                pickedWordsJSON: pickedWords.isEmpty ? nil : try? JSONEncoder().encode(pickedWords)
            )
            context.insert(saved)
            try context.save()
            return saved
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Rehydrates the full in-memory song (audio bytes + timings + scenes) for
    /// playback and karaoke. nil when the mp3 was deleted from disk.
    func asMusicSong() -> ProxyClient.MusicSong? {
        guard let data = try? Data(contentsOf: audioURL) else { return nil }
        let lines = (try? JSONDecoder().decode([ProxyClient.MusicLyricLine].self, from: linesJSON)) ?? []
        let scenes = (try? JSONDecoder().decode([ProxyClient.MusicScene].self, from: scenesJSON)) ?? []
        return ProxyClient.MusicSong(
            title: title,
            lyrics: lyrics,
            genre: genre,
            durationSec: durationSec,
            audioData: data,
            mime: "audio/mpeg",
            lines: lines,
            scenes: scenes
        )
    }
}
