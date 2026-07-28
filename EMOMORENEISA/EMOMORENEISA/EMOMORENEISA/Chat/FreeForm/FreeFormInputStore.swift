import UIKit

/// Mirrors StreetViewPhotoStore's handoff: NewSessionView's free-form entry
/// screen creates the session and stashes whatever the student typed/
/// attached there (before ChatView even exists), and ChatView's
/// openingMessage() consumes it once, on first appearance, to build the
/// session's real opening user message.
final class FreeFormInputStore {
    static let shared = FreeFormInputStore()
    private init() {}

    private var store: [UUID: (text: String?, images: [UIImage])] = [:]

    func set(text: String?, images: [UIImage], for sessionId: UUID) {
        store[sessionId] = (text, images)
    }

    func consume(for sessionId: UUID) -> (text: String?, images: [UIImage])? {
        defer { store.removeValue(forKey: sessionId) }
        return store[sessionId]
    }
}
