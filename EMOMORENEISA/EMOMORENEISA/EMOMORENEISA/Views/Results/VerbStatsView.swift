import SwiftUI
import SwiftData

/// Stats screen for the verb-conjugation game — every word attempt ever
/// played, including partial/abandoned rounds (see `VerbAttempt`). Mirrors
/// `LoroStatsView`'s structure (summary tiles → chart → per-item list) but
/// styled to match the verb game's own screens (`GameBackground`,
/// `GameColors`, monospaced type) rather than the Memorize feature's lighter
/// `AppBackground`/`AppColors` theme.
struct VerbStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VerbAttempt.createdAt, order: .reverse) private var attempts: [VerbAttempt]

    private var gamesPlayed: Int { Set(attempts.map(\.roundId)).count }
    private var totalWords: Int { attempts.count }
    private var correctCount: Int { attempts.filter(\.correct).count }
    private var accuracyPercent: Int {
        totalWords == 0 ? 0 : Int(((Double(correctCount) / Double(totalWords)) * 100).rounded())
    }

    private struct DayBucket: Identifiable {
        let day: Date
        var correct: Int
        var missed: Int
        var id: Date { day }
        var total: Int { correct + missed }
    }

    /// Last 14 days, oldest → newest, gaps filled with zero so the chart
    /// reads left-to-right consistently even on days nothing was played.
    private var dailyBuckets: [DayBucket] {
        let calendar = Calendar.current
        var byDay: [Date: DayBucket] = [:]
        for attempt in attempts {
            let day = calendar.startOfDay(for: attempt.createdAt)
            var bucket = byDay[day] ?? DayBucket(day: day, correct: 0, missed: 0)
            if attempt.correct { bucket.correct += 1 } else { bucket.missed += 1 }
            byDay[day] = bucket
        }
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return byDay[day] ?? DayBucket(day: day, correct: 0, missed: 0)
        }
    }

    private struct VerbTally: Identifiable {
        let infinitive: String
        var correct: Int
        var total: Int
        var id: String { infinitive }
    }

    private var verbTallies: [VerbTally] {
        var byVerb: [String: VerbTally] = [:]
        for attempt in attempts {
            var tally = byVerb[attempt.verbInfinitive]
                ?? VerbTally(infinitive: attempt.verbInfinitive, correct: 0, total: 0)
            tally.total += 1
            if attempt.correct { tally.correct += 1 }
            byVerb[attempt.verbInfinitive] = tally
        }
        return byVerb.values.sorted { $0.total > $1.total }
    }

    var body: some View {
        ZStack {
            GameBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if attempts.isEmpty {
                        emptyState
                    } else {
                        summaryTiles
                        dailyChartCard
                        verbListCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            BackButton { dismiss() }
            Spacer()
            Text(L("VERB STATS"))
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .tracking(3)
            Spacer()
            // Balances the BackButton so the title stays visually centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 54)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Text(L("No rounds played yet"))
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
            Text(L("Play a round of Verbs & Times to start building your stats."))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Summary tiles

    private var summaryTiles: some View {
        HStack(spacing: 12) {
            statTile(label: L("Games played"), value: "\(gamesPlayed)", color: GameColors.gold)
            statTile(label: L("Words"), value: "\(totalWords)", color: .white)
            statTile(label: L("Accuracy"), value: "\(accuracyPercent)%",
                     color: accuracyPercent >= 70 ? GameColors.verde : GameColors.rojo)
        }
    }

    private func statTile(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.45), radius: 6)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Daily chart

    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("LAST 14 DAYS"))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
                .tracking(2)

            let maxTotal = max(1, dailyBuckets.map(\.total).max() ?? 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(dailyBuckets) { bucket in
                    VStack(spacing: 1) {
                        if bucket.missed > 0 {
                            Capsule()
                                .fill(GameColors.rojo.opacity(0.75))
                                .frame(height: max(3, 46 * CGFloat(bucket.missed) / CGFloat(maxTotal)))
                        }
                        if bucket.correct > 0 {
                            Capsule()
                                .fill(GameColors.verde.opacity(0.85))
                                .frame(height: max(3, 46 * CGFloat(bucket.correct) / CGFloat(maxTotal)))
                        }
                        if bucket.total == 0 {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .frame(height: 46)
                }
            }

            HStack(spacing: 14) {
                legendDot(color: GameColors.verde, label: L("Correct"))
                legendDot(color: GameColors.rojo, label: L("Missed"))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Per-verb tally

    private var verbListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("BY VERB"))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.40))
                .tracking(2)

            ForEach(verbTallies) { tally in
                HStack(spacing: 12) {
                    Text(tally.infinitive)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(tally.correct)/\(tally.total)")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundColor(tally.correct == tally.total ? GameColors.verde : GameColors.gold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
        }
    }
}
