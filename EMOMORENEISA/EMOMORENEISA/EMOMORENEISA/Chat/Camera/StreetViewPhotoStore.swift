import UIKit

final class StreetViewPhotoStore {
    static let shared = StreetViewPhotoStore()
    private init() {}

    private var store: [UUID: [UIImage]] = [:]

    func set(_ images: [UIImage], for sessionId: UUID) {
        store[sessionId] = images
    }

    func consume(for sessionId: UUID) -> [UIImage]? {
        defer { store.removeValue(forKey: sessionId) }
        return store[sessionId]
    }
}
