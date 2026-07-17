import SwiftUI
import StoreKit

struct BillingInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StoreManager.shared

    private let termsURL = URL(string: "https://professormadrid.com/terms")
    private let privacyURL = URL(string: "https://professormadrid.com/privacy")

    private struct Activity: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let cost: String
        let note: String
    }

    // Mirrors server config.actionCosts (treats per action) exactly — see
    // server/src/config.js. Every entry here corresponds to a real debit();
    // there is no free daily allowance for anything in this list.
    private let activities: [Activity] = [
        Activity(icon: "bubble.left.and.bubble.right.fill", name: L("Chat reply"),
                 cost: L("~5 treats"), note: L("A full AI answer from your tutor.")),
        Activity(icon: "speaker.wave.2.fill", name: L("Voice line"),
                 cost: L("~2 treats"), note: L("Hearing a reply spoken aloud.")),
        Activity(icon: "map.fill", name: L("Street View photo chat"),
                 cost: L("~9 treats"), note: L("Asking the tutor about a photo you've taken.")),
        Activity(icon: "tag.fill", name: L("Street View photo labels"),
                 cost: L("~6 treats"), note: L("Identifying and labelling objects in your photo.")),
        Activity(icon: "plus.circle.fill", name: L("Add to Memorise"),
                 cost: L("~3 treats"), note: L("Generates the repeat-audio and picture for a new word or phrase.")),
        Activity(icon: "checkmark.bubble.fill", name: L("Verb check"),
                 cost: L("~2 treats"), note: L("Checking your spoken answer in Verbs & Times."))
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                        whatAreTreats
                        whatUsesTreats
                        waysToSave
                        howTopUpsWork
                        howWeCalculate
                        goodToKnow
                        legalLinks
                    }
                    .padding()
                }
            }
            .navigationTitle(L("How treats work"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .tint(.yellow)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Image("paywall_seagull")
                .resizable()
                .scaledToFit()
                .frame(height: 72)
            Text(L("Treats power your Spanish"))
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(L("Treats are the credit that runs the AI features — chat, voice, Street View and drills. You buy them once and spend them as you learn."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private var whatAreTreats: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("What are treats?"))
            Text(L("Every reply, spoken line and photo is generated live by AI, which has a real cost on our side. Treats are how that cost is shared fairly: simple actions use a little, richer ones use a bit more. New accounts start with free treats so you can try everything before paying."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var whatUsesTreats: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L("What uses treats"))
            VStack(spacing: 10) {
                ForEach(activities) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, design: .rounded))
                            .frame(width: 28)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.cost)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Text(L("Amounts are approximate and may be adjusted over time."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var waysToSave: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("Ways to spend less"))
            bullet(L("Turn off automatic voice replies in Profile and tap a message only when you want to hear it — voice is the easiest way to save."))
            bullet(L("Chatting in text uses the fewest treats."))
        }
    }

    private var howTopUpsWork: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("How top-ups work"))
            Text(L("Pick any pack to add treats instantly. Bigger packs include bonus treats, so you get more for each dollar:"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(StoreManager.packCatalog) { pack in
                    let product = store.products.first { $0.id == pack.id }
                    packRow(
                        price: product?.displayPrice ?? "—",
                        treats: L("%@ treats", pack.treats.formatted()),
                        bonus: pack.bonusLabel
                    )
                }
            }
            .task { store.start() }
        }
    }

    private func packRow(price: String, treats: String, bonus: String?) -> some View {
        HStack {
            Text(price).font(.subheadline.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(treats).font(.subheadline)
                if let bonus {
                    Text(bonus).font(.caption.weight(.bold)).foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var howWeCalculate: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("How we calculate"))
            Text(L("Treat costs reflect the real work behind each action: a longer answer or a spoken line costs a little more than a short text reply. We round everything to simple, predictable amounts so you always have a rough idea of what you're spending — no surprises, no per-word meter."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("Good to know"))
            bullet(L("Treats never expire."))
            bullet(L("Treat packs are one-time purchases, not a subscription — you're never charged automatically."))
            bullet(L("When you run low, top up any pack to keep going."))
        }
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(spacing: 20) {
                if let termsURL { Link(L("Terms & Conditions"), destination: termsURL) }
                if let privacyURL { Link(L("Privacy Policy"), destination: privacyURL) }
            }
            .font(.footnote)
        }
        .padding(.top, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.subheadline.weight(.bold)).foregroundStyle(.tint)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
