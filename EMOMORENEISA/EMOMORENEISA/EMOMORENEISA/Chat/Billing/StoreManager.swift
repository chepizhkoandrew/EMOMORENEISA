import Foundation
import StoreKit
import Observation

// Treat pack metadata: product id -> headline shown on the paywall.
struct TreatPack: Identifiable {
    let id: String          // StoreKit product id
    let treats: Int         // treats credited on purchase
    let bonusLabel: String?  // e.g. "+15% bonus"
    var headline: String { "\(treats.formatted()) treats" }
}

@Observable
@MainActor
final class StoreManager {
    static let shared = StoreManager()

    // Order defines display order on the paywall (cheapest -> whale).
    static let packCatalog: [TreatPack] = [
        TreatPack(id: "treats_starter_599",  treats: 599,   bonusLabel: nil),
        TreatPack(id: "treats_plus_1199",    treats: 1_379, bonusLabel: "+15% bonus"),
        TreatPack(id: "treats_pro_2499",     treats: 3_124, bonusLabel: "+25% bonus"),
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

        AnalyticsService.shared.track(.purchaseStarted(productId: product.id))

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
                if credited {
                    let treats = pack(for: product.id)?.treats ?? 0
                    AnalyticsService.shared.track(.purchaseCompleted(productId: product.id, treats: treats))
                }
                return credited
            case .userCancelled:
                AnalyticsService.shared.track(.purchaseCancelled(productId: product.id))
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
