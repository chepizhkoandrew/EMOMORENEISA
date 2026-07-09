import Foundation
import Observation

// Client-side mirror of the server treat wallet. The server is the source of
// truth; this caches the last known balance and drives the paywall.
@Observable
@MainActor
final class WalletManager {
    static let shared = WalletManager()
    private init() {}

    var balanceTreats: Int = 0
    var hasPaid: Bool = false
    var trialGranted: Bool = false
    var isLoaded: Bool = false

    // Drives the paywall sheet from anywhere in the app.
    var showPaywall: Bool = false

    // Called once right after sign-in: ensures the wallet exists and grants the trial.
    func bootstrap() async {
        guard AuthState.shared.isSignedIn else { return }
        if let state = try? await ProxyClient.shared.bootstrap() {
            apply(state)
        }
    }

    func refresh() async {
        guard AuthState.shared.isSignedIn else { return }
        if let state = try? await ProxyClient.shared.wallet() {
            apply(state)
        }
    }

    func apply(_ state: ProxyClient.WalletState) {
        balanceTreats = state.balanceTreats
        hasPaid = state.hasPaid
        trialGranted = state.trialGranted
        isLoaded = true
    }

    // Invoked by ProxyClient when any billable call returns 402.
    func handleInsufficientTreats(balance: Int) {
        balanceTreats = balance
        showPaywall = true
        AnalyticsService.shared.track(.paywallShown(balance: balance))
    }
}
