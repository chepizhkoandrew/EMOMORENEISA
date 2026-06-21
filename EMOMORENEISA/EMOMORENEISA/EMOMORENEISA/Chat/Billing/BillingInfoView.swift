import SwiftUI

// Customer-facing explainer for the treat (credit) system, presented from the
// paywall. It answers "what are treats / what uses them / how top-ups work /
// how we calculate" in plain language. No margins or COGS are exposed here.
//
// The treat amounts below MIRROR the server source of truth in
// server/src/config.js (actionCosts + packs + trialGrantTreats). They are shown
// as approximate, friendly figures so users understand how treats are spent.
// If the server costs change, update these constants to match.
struct BillingInfoView: View {
    @Environment(\.dismiss) private var dismiss

    private let termsURL = URL(string: "https://professormadrid.com/terms")
    private let privacyURL = URL(string: "https://professormadrid.com/privacy")

    private struct Activity: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let cost: String
        let note: String
    }

    // Mirrors server config.actionCosts (treats per action).
    private let activities: [Activity] = [
        Activity(icon: "bubble.left.and.bubble.right.fill", name: "Chat reply",
                 cost: "~5 treats", note: "A full AI answer from your tutor."),
        Activity(icon: "speaker.wave.2.fill", name: "Voice line",
                 cost: "~2 treats", note: "Hearing a reply spoken aloud."),
        Activity(icon: "map.fill", name: "Street View photo",
                 cost: "20 free / day, then ~9", note: "Browsing the world for context."),
        Activity(icon: "repeat", name: "Loro drill",
                 cost: "~3 treats", note: "A repeat-after-me pronunciation set."),
        Activity(icon: "text.magnifyingglass", name: "Word help",
                 cost: "~6 treats", note: "Tap a word for a deeper explanation.")
    ]

    var body: some View {
        NavigationStack {
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
            .navigationTitle("How treats work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text("🦜")
                .font(.system(size: 48))
            Text("Treats power your Spanish")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Treats are the credit that runs the AI features — chat, voice, Street View and drills. You buy them once and spend them as you learn.")
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
            sectionTitle("What are treats?")
            Text("Every reply, spoken line and photo is generated live by AI, which has a real cost on our side. Treats are how that cost is shared fairly: simple actions use a little, richer ones use a bit more. New accounts start with free treats so you can try everything before paying.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var whatUsesTreats: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What uses treats")
            VStack(spacing: 10) {
                ForEach(activities) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
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
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Amounts are approximate and may be adjusted over time.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var waysToSave: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Ways to spend less")
            bullet("Turn off automatic voice replies in Profile and tap a message only when you want to hear it — voice is the easiest way to save.")
            bullet("Street View gives you 20 free photos every day before any treats are used.")
            bullet("Chatting in text uses the fewest treats.")
        }
    }

    private var howTopUpsWork: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("How top-ups work")
            Text("Pick any pack to add treats instantly. Bigger packs include bonus treats, so you get more for each dollar:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                packRow(price: "$5.99", treats: "599 treats", bonus: nil)
                packRow(price: "$11.99", treats: "1,379 treats", bonus: "+15% bonus")
                packRow(price: "$24.99", treats: "3,124 treats", bonus: "+25% bonus")
                packRow(price: "$49.99", treats: "7,399 treats", bonus: "Best value · +48%")
            }
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var howWeCalculate: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("How we calculate")
            Text("Treat costs reflect the real work behind each action: a longer answer or a spoken line costs a little more than a short text reply. We round everything to simple, predictable amounts so you always have a rough idea of what you're spending — no surprises, no per-word meter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Good to know")
            bullet("Treats never expire.")
            bullet("Treat packs are one-time purchases, not a subscription — you're never charged automatically.")
            bullet("When you run low, top up any pack to keep going.")
        }
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(spacing: 20) {
                if let termsURL { Link("Terms & Conditions", destination: termsURL) }
                if let privacyURL { Link("Privacy Policy", destination: privacyURL) }
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
