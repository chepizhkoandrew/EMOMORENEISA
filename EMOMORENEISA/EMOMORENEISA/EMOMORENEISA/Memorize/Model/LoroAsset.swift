import SwiftUI
import UIKit

/// Named El Loro art slots (spec §2.2). Art production is an out-of-code Phase 2
/// dependency; every slot has an emoji fallback so the app builds and runs
/// before the seagull-in-a-parrot-costume art is delivered. Never generate art
/// in code — only reference named asset slots.
enum LoroAsset: String, CaseIterable {
    case idle      = "loro_idle"
    case listening = "loro_listening"
    case happy     = "loro_happy"
    case excited   = "loro_excited"
    case teaching  = "loro_teaching"
    case sleeping  = "loro_sleeping"
    case sad       = "loro_sad"

    /// Text shown until the named art asset is added to the catalog.
    var textFallback: String {
        switch self {
        case .idle:      return "~"
        case .listening: return "~"
        case .happy:     return "~"
        case .excited:   return "~"
        case .teaching:  return "~"
        case .sleeping:  return "~"
        case .sad:       return "~"
        }
    }

    /// True once a real image asset has been delivered for this slot.
    var hasArt: Bool { UIImage(named: rawValue) != nil }
}

/// Renders an El Loro pose, falling back to its emoji when art is not yet
/// present so layouts never break before assets land.
struct LoroImage: View {
    let asset: LoroAsset
    var size: CGFloat = 120

    var body: some View {
        if asset.hasArt {
            Image(asset.rawValue)
                .resizable()
                .scaledToFit()
                .frame(height: size)
        } else {
            Text(asset.textFallback)
                .font(.system(size: size * 0.8))
        }
    }
}
