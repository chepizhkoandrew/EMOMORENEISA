import SwiftUI

/// The five user-visible memory stages. The 13 internal sub-phases compress to
/// these five — expressed as how long El Loro will remember the word and what
/// material it is written in. This is the ONLY phase language the user sees.
/// Spec §3. Centralized here so the 13→5 mapping never leaks into views.
enum MemoryStage: Int, CaseIterable {
    case agua = 0
    case wood
    case stone
    case gold
    case microchip

    /// Spec §3.1 table: 0–1 → agua, 2–5 → wood, 6–10 → stone, 11–12 → gold, ≥13 → microchip.
    nonisolated static func stage(forExposureCount exposureCount: Int) -> MemoryStage {
        switch exposureCount {
        case ..<2:    return .agua       // 0–1
        case 2...5:   return .wood
        case 6...10:  return .stone
        case 11...12: return .gold
        default:      return .microchip  // ≥13
        }
    }

    /// Position 0…4 used by the horizon strip and per-card progress indicator.
    nonisolated var progressIndex: Int { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .agua:      return "Agua"
        case .wood:      return "Wood"
        case .stone:     return "Stone"
        case .gold:      return "Gold"
        case .microchip: return "Microchip"
        }
    }

    nonisolated var materialName: String {
        switch self {
        case .agua:      return "Water"
        case .wood:      return "Wood"
        case .stone:     return "Stone"
        case .gold:      return "Gold"
        case .microchip: return "Microchip"
        }
    }

    /// User-facing forgetting horizon. Spec §3.1.
    nonisolated var horizonLabel: String {
        switch self {
        case .agua:      return "~1 hour"
        case .wood:      return "~3 days"
        case .stone:     return "~1 month"
        case .gold:      return "~1 year"
        case .microchip: return "~5 years"
        }
    }

    /// One-line description of how durable the memory is at this stage.
    nonisolated var horizonSentence: String {
        switch self {
        case .agua:      return "Loro forgets in ~1 hour without practice."
        case .wood:      return "Loro forgets in ~3 days without practice."
        case .stone:     return "Loro forgets in ~1 month without practice."
        case .gold:      return "Loro forgets in ~1 year without practice."
        case .microchip: return "Loro won't forget it for ~5 years."
        }
    }

    /// SF Symbol placeholder shown until the material token art is delivered.
    nonisolated var placeholderSymbol: String {
        switch self {
        case .agua:      return "drop.fill"
        case .wood:      return "leaf.fill"
        case .stone:     return "mountain.2.fill"
        case .gold:      return "crown.fill"
        case .microchip: return "cpu.fill"
        }
    }

    /// Named material-token asset slot (art is a Phase 2 dependency; falls back
    /// to `placeholderSymbol` until delivered).
    nonisolated var assetName: String {
        switch self {
        case .agua:      return "material_agua"
        case .wood:      return "material_wood"
        case .stone:     return "material_stone"
        case .gold:      return "material_gold"
        case .microchip: return "material_microchip"
        }
    }

    var tokenColor: Color {
        switch self {
        case .agua:      return Color(red: 0.35, green: 0.78, blue: 0.98)   // water blue
        case .wood:      return Color(red: 0.62, green: 0.43, blue: 0.24)   // wood brown
        case .stone:     return Color(red: 0.62, green: 0.64, blue: 0.68)   // stone gray
        case .gold:      return Color(red: 0.98, green: 0.80, blue: 0.18)   // gold
        case .microchip: return Color(red: 0.30, green: 0.86, blue: 0.55)   // microchip green
        }
    }

    /// Compact label for the five-stop forgetting-horizon strip. Spec §3.4.
    nonisolated var stripLabel: String {
        switch self {
        case .agua:      return "1h"
        case .wood:      return "3d"
        case .stone:     return "1mo"
        case .gold:      return "1yr"
        case .microchip: return "5yr"
        }
    }
}
