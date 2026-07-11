import Network
import Foundation

// Lightweight connectivity signal for gating network-dependent flows (the
// onboarding voice quiz needs a live connection for every probe/synthesis
// call — starting it offline just produces silent fallbacks that look like
// crashes). Not a general-purpose reachability library — just "satisfied and
// not obviously constrained" vs. everything else.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var isLikelySlow: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                // Not a bandwidth test — just a coarse "expect this to be
                // rough" signal (cellular data-saver mode, hotspot limits).
                self?.isLikelySlow = path.isExpensive || path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }
}
