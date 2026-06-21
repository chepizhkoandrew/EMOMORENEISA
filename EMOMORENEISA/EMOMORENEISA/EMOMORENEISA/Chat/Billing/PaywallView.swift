import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreManager.shared
    @State private var wallet = WalletManager.shared
    @State private var showInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if store.isLoadingProducts && store.products.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if store.products.isEmpty {
                        Text("Packs are unavailable right now. Please try again in a moment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            packRow(product)
                        }
                    }

                    if let err = store.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showInfo = true
                    } label: {
                        Label("How treats work", systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 4)

                    Text("Treats never expire. Bigger packs include bonus treats. One-time purchase — no subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Get Treats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showInfo) {
                BillingInfoView()
            }
            .task {
                store.start()
                await wallet.refresh()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("🦜")
                .font(.system(size: 52))
            Text("\(wallet.balanceTreats) treats")
                .font(.title2.bold())
            Text("Pick a pack to keep your lessons going.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func packRow(_ product: Product) -> some View {
        let pack = store.pack(for: product.id)
        let isBuying = store.purchaseInProgress == product.id
        return Button {
            Task { await store.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName.isEmpty ? product.id : product.displayName)
                        .font(.headline)
                    if let pack {
                        Text(pack.headline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let bonus = pack?.bonusLabel {
                        Text(bonus)
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if isBuying {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInProgress != nil)
    }
}
