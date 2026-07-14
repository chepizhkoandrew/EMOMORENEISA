import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var store = StoreManager.shared
    @State private var wallet = WalletManager.shared
    @State private var showInfo = false
    @State private var treatsBump = false

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
                .ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    if let img = UIImage(named: "paywall_seagull") {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width)
                            .mask(
                                LinearGradient(
                                    colors: [.black, .black.opacity(0.75), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    Spacer()
                }
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    Color.clear.frame(height: 220)

                        VStack(spacing: 6) {
                            Text(L("%@ treats", wallet.balanceTreats.formatted()))
                                .font(.title.bold())
                                .foregroundStyle(.white)
                                .contentTransition(.numericText(value: Double(wallet.balanceTreats)))
                                .animation(.snappy(duration: 0.6), value: wallet.balanceTreats)
                                .scaleEffect(treatsBump ? 1.18 : 1.0)
                                .shadow(color: .green.opacity(treatsBump ? 0.7 : 0), radius: treatsBump ? 16 : 0)
                                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: treatsBump)
                                .onChange(of: wallet.balanceTreats) { oldValue, newValue in
                                    guard newValue > oldValue else { return }
                                    treatsBump = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(0.45))
                                        treatsBump = false
                                    }
                                }
                            Text(L("Pick a pack to keep your lessons going."))
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)

                        if store.isLoadingProducts && store.products.isEmpty {
                            ProgressView().tint(.white).padding(.top, 40)
                        } else if store.products.isEmpty {
                            Text(L("Packs are unavailable right now. Please try again in a moment."))
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
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

                        costSummary

                        Button { showInfo = true } label: {
                            Label(L("Full pricing details"), systemImage: "info.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.top, 2)

                        Text(L("Treats never expire. One-time purchase — no subscription."))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
        }
        .navigationTitle(L("Get Treats"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .sheet(isPresented: $showInfo) {
            BillingInfoView()
        }
        .onDisappear {
            AnalyticsService.shared.track(.paywallDismissed)
        }
        .task {
            store.start()
            await wallet.refresh()
        }
    }

    private func packRow(_ product: Product) -> some View {
        let pack = store.pack(for: product.id)
        let isBuying = store.purchaseInProgress == product.id
        return Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let pack {
                        Text(pack.headline)
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text(product.displayName.isEmpty ? product.id : product.displayName)
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    if let bonus = pack?.bonusLabel {
                        Text(bonus)
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                if isBuying {
                    ProgressView().tint(.white)
                } else {
                    Text(product.displayPrice)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInProgress != nil)
    }

    private var costSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("What treats cost"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            VStack(spacing: 6) {
                costRow(icon: "bubble.left.and.bubble.right.fill", label: L("Chat reply"), cost: L("~5 treats"))
                costRow(icon: "speaker.wave.2.fill", label: L("Voice line"), cost: L("~2 treats"))
                costRow(icon: "camera.fill", label: L("Street View photo chat"), cost: L("~9 treats"))
                costRow(icon: "tag.fill", label: L("Street View photo labels"), cost: L("~6 treats"))
                costRow(icon: "plus.circle.fill", label: L("Add to Memorise"), cost: L("~3 treats"))
                costRow(icon: "checkmark.bubble.fill", label: L("Verb check"), cost: L("~2 treats"))
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private func costRow(icon: String, label: String, cost: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text(cost)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

}
