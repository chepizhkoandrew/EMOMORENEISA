import SwiftUI
import StoreKit

private enum CouponState: Equatable {
    case idle
    case loading
    case success(Int)
    case failure(String)
}

struct PaywallView: View {
    @State private var store = StoreManager.shared
    @State private var wallet = WalletManager.shared
    @State private var showInfo = false
    @State private var showCouponField = false
    @State private var couponCode = ""
    @State private var couponState: CouponState = .idle
    @FocusState private var couponFocused: Bool

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

                        couponSection

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
                costRow(icon: "camera.fill", label: L("Street View photo"), cost: L("20 free/day, then ~9"))
                costRow(icon: "repeat", label: L("Loro drill"), cost: L("~3 treats"))
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

    private var couponSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCouponField.toggle()
                    if !showCouponField {
                        couponCode = ""
                        couponState = .idle
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showCouponField ? "chevron.up" : "ticket")
                        .imageScale(.small)
                    Text(L("Have a coupon code?"))
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            if showCouponField {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        TextField(L("Enter code"), text: $couponCode)
                            .textCase(.uppercase)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .focused($couponFocused)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppColors.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.inputBorder, lineWidth: 1))
                            .onChange(of: couponCode) { _, _ in
                                if couponState != .idle && couponState != .loading {
                                    couponState = .idle
                                }
                            }

                        Button {
                            Task { await submitCoupon() }
                        } label: {
                            Group {
                                if couponState == .loading {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: 48, height: 36)
                                } else {
                                    Text(L("Apply"))
                                        .font(.subheadline.bold())
                                        .frame(width: 48, height: 36)
                                }
                            }
                            .padding(.horizontal, 8)
                            .background(couponCode.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.35) : Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(couponCode.trimmingCharacters(in: .whitespaces).isEmpty || couponState == .loading)
                        .buttonStyle(.plain)
                    }

                    switch couponState {
                    case .idle:
                        EmptyView()
                    case .loading:
                        EmptyView()
                    case .success(let treats):
                        Label(L("%@ treats added to your balance!", treats.formatted()), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private func submitCoupon() async {
        let code = couponCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        couponFocused = false
        couponState = .loading
        do {
            let result = try await ProxyClient.shared.redeemCoupon(code: code)
            WalletManager.shared.apply(result.walletState)
            couponState = .success(result.creditedTreats)
            couponCode = ""
            AnalyticsService.shared.track(.couponRedeemed(treats: result.creditedTreats))
        } catch ProxyError.http(_, let message) {
            couponState = .failure(couponErrorMessage(for: message))
        } catch {
            couponState = .failure(L("Something went wrong. Please try again."))
        }
    }

    private func couponErrorMessage(for serverCode: String) -> String {
        switch serverCode {
        case "not_found", "inactive": return L("This coupon code is not valid.")
        case "expired": return L("This coupon has expired.")
        case "max_uses": return L("This coupon has reached its usage limit.")
        case "already_redeemed": return L("You've already redeemed this coupon.")
        default: return L("Something went wrong. Please try again.")
        }
    }
}
