import Foundation
import StoreKit
import Observation

// Treat pack metadata: product id -> headline shown on the paywall.
struct TreatPack: Identifiable {
    let id: String          // StoreKit product id
    let headline: String    // e.g. "~14 conversations"
    let bonusLabel: String?  // e.g. "+15% bonus"
}

@Observable
@MainActor
final class StoreManager {
    static let shared = StoreManager()

    // Order defines display order on the paywall (cheapest -> whale).
    static let packCatalog: [TreatPack] = [
        TreatPack(id: "treats_599",  headline: "~6 conversations",  bonusLabel: nil),
        TreatPack(id: "treats_1199", headline: "~14 conversations", bonusLabel: "+15% bonus"),
        TreatPack(id: "treats_2499", headline: "~31 conversations", bonusLabel: "+25% bonus"),
        TreatPack(id: "treats_4999", headline: "~74 conversations", bonusLabel: "Best value · +48%")
    ]

    var products: [Product] = []
    var isLoadingProducts = false
    var purchaseInProgress: String? = nil   // product id currently being purchased
    var lastError: String? = nil

    private var updatesTask: Task<Void, Never>? = nil
    private init() {}

    func start() {
        if updatesTask == nil {
            updatesTask = listenForTransactions()
        }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let ids = Set(Self.packCatalog.map { $0.id })
            let fetched = try await Product.products(for: ids)
            // Preserve catalog order.
            products = Self.packCatalog.compactMap { pack in fetched.first { $0.id == pack.id } }
        } catch {
            lastError = "Could not load products."
        }
    }

    func pack(for id: String) -> TreatPack? { Self.packCatalog.first { $0.id == id } }

    // Purchases a consumable, sends the signed JWS to the proxy for verification +
    // crediting, then finishes the transaction. Returns true on success.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = product.id
        lastError = nil
        defer { purchaseInProgress = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Could not verify the purchase."
                    return false
                }
                let credited = await creditOnServer(jws: verification.jwsRepresentation)
                await transaction.finish()
                return credited
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "Purchase failed. Please try again."
            return false
        }
    }

    // Re-sends any unfinished consumable transactions to the server (e.g. after a
    // crash between purchase and crediting).
    func restoreUnfinished() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            let ok = await creditOnServer(jws: result.jwsRepresentation)
            if ok { await transaction.finish() }
        }
    }

    private func creditOnServer(jws: String) async -> Bool {
        do {
            let state = try await ProxyClient.shared.topup(signedTransaction: jws)
            WalletManager.shared.apply(state)
            WalletManager.shared.showPaywall = false
            return true
        } catch {
            lastError = "Couldn't credit treats. They will be retried automatically."
            return false
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                let ok = await self?.creditOnServer(jws: result.jwsRepresentation) ?? false
                if ok { await transaction.finish() }
            }
        }
    }
}
