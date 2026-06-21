import Foundation
import SwiftData
import UIKit

@Observable
final class AnnotationService {
    enum State {
        case idle
        case loading
        case ready([AnnotationItem])
        case failed(String)
    }

    var state: State = .idle

    func load(
        assistantMessage: LocalChatMessage,
        userMessage: LocalChatMessage,
        existing: StreetAnnotation?,
        modelContext: ModelContext
    ) async {
        if let existing, !existing.annotations.isEmpty {
            await MainActor.run { state = .ready(existing.annotations) }
            return
        }

        await MainActor.run { state = .loading }

        let images = userMessage.resolvedImagePaths.compactMap { UIImage(contentsOfFile: $0) }
        let imageData = images.compactMap { $0.jpegData(compressionQuality: 0.72) }

        guard !imageData.isEmpty else {
            await MainActor.run { state = .failed("No image found for this message.") }
            return
        }

        let objectList = assistantMessage.textContent ?? ""

        do {
            let result = try await ProxyClient.shared.annotate(
                imageData: imageData,
                objectList: objectList
            )

            guard !result.annotations.isEmpty else {
                await MainActor.run { state = .failed("No annotations returned.") }
                return
            }

            let annotation = StreetAnnotation(
                assistantMessageId: assistantMessage.id,
                userMessageId: userMessage.id,
                sessionId: assistantMessage.sessionId,
                annotationsJSON: result.annotationsJSON
            )
            await MainActor.run {
                modelContext.insert(annotation)
                try? modelContext.save()
                state = .ready(result.annotations)
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
}
