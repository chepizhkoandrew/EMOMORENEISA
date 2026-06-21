import SwiftUI

struct GameMatrixView: View {
    @EnvironmentObject var engine: GameEngine
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isReview: Bool { engine.phase == .review }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            GameBackground()

            ScrollView(isLandscape ? .vertical : []) {
                VStack(spacing: 0) {
                    topBar
                    if !isLandscape {
                        guidanceBanner
                    }
                    headerRow
                    Divider().background(Color.white.opacity(0.12))
                    matrixBody
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                engine.newRound()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(isReview ? "NEW ROUND" : "STOP")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.09))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            }

            if isReview {
                HStack(spacing: 6) {
                    Text("REVIEW")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .tracking(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(GameColors.gold)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if isReview {
                reviewControls
            }
        }
        .padding(.bottom, 6)
    }

    private var reviewControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { engine.hideCorrect.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.hideCorrect ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .bold))
                    Text(engine.hideCorrect ? "SHOW ALL" : "HIDE ✓")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(engine.hideCorrect ? GameColors.gold : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    engine.hideCorrect ? GameColors.gold.opacity(0.4) : Color.white.opacity(0.12),
                    lineWidth: 1
                ))
            }

            Button {
                engine.repeatRound()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text("REPEAT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(GameColors.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(GameColors.gold.opacity(0.35), lineWidth: 1))
            }

            Button {
                engine.enterResults()
            } label: {
                Text("SUMMARY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }

    // MARK: - Guidance banner

    private var guidanceBanner: some View {
        Group {
            if let cell = engine.currentActiveCell {
                activeBanner(cell: cell)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let result = engine.lastResult {
                resultBanner(result: result)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if isReview {
                reviewIdleBanner
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: engine.currentActiveCell?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: engine.lastResult?.pronoun)
        .animation(.easeInOut(duration: 0.2), value: isReview)
    }

    private func activeBanner(cell: GameCell) -> some View {
        let (knownStem, endingBlanks) = stemAndBlanks(infinitive: cell.verb.infinitive, conjugation: cell.expectedConjugation)
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(GameColors.gold.opacity(0.35), lineWidth: 1.5)
                )

            HStack(spacing: 0) {
                Color.clear.frame(width: 96 + 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cell.pronoun.displayLabel.uppercased())
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(GameColors.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: GameColors.gold.opacity(0.7), radius: 8)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if !knownStem.isEmpty {
                            Text(knownStem)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(color: .white.opacity(0.3), radius: 5)
                        }
                        Text(endingBlanks.isEmpty ? "_" : endingBlanks)
                            .font(.system(size: 18, weight: .light, design: .monospaced))
                            .foregroundColor(.white.opacity(0.22))
                            .tracking(4)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.vertical, 4)
    }

    private func resultBanner(result: GameEngine.LastResult) -> some View {
        let color: Color = result.correct ? GameColors.verde : GameColors.rojo
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.35), lineWidth: 1.5)
                )

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.pronoun.uppercased())
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundColor(color.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(result.conjugation)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: color.opacity(0.6), radius: 8)
                }

                if !result.userTranscript.isEmpty && !result.correct {
                    Text("you said: \"\(result.userTranscript)\"")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(GameColors.rojo.opacity(0.60))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if result.correct {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("CORRECT")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(GameColors.verde.opacity(0.80))
                    .shadow(color: GameColors.verde.opacity(0.5), radius: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.vertical, 4)
    }

    private var reviewIdleBanner: some View {
        let missedCount = engine.round?.cells.filter { $0.state == .missed }.count ?? 0
        let color: Color = missedCount == 0 ? GameColors.verde : GameColors.rojo
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )

            VStack(spacing: 4) {
                Text(missedCount == 0 ? "ALL CORRECT" : "TAP A RED CELL TO RETRY")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(missedCount == 0 ? GameColors.verde : .white.opacity(0.60))
                    .shadow(color: missedCount == 0 ? GameColors.verde.opacity(0.6) : .clear, radius: 8)

                if missedCount > 0 {
                    Text("\(missedCount) MISSED")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(GameColors.rojo.opacity(0.65))
                        .tracking(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.vertical, 4)
    }

    private func stemAndBlanks(infinitive: String, conjugation: String) -> (stem: String, blanks: String) {
        let rawStem = infinitive.count > 2 ? String(infinitive.dropLast(2)).lowercased() : ""
        let conjLower = conjugation.lowercased()
        let stemChars = Array(rawStem)
        let conjChars = Array(conjLower)
        var commonLen = 0
        for i in 0..<min(stemChars.count, conjChars.count) {
            if stemChars[i] == conjChars[i] { commonLen += 1 } else { break }
        }
        let knownStem = String(conjugation.prefix(commonLen)).uppercased()
        let endingPart = String(conjugation.dropFirst(commonLen))
        let endingBlanks = endingPart.map { _ in "_" }.joined(separator: " ")
        return (knownStem, endingBlanks)
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 96)

            ForEach(Array(engine.selectedVerbs.enumerated()), id: \.offset) { _, verb in
                VerbChip(verb: verb)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, isLandscape ? 5 : 10)
    }

    // MARK: - Matrix

    private var matrixBody: some View {
        VStack(spacing: isLandscape ? 3 : 5) {
            ForEach(Pronoun.allCases) { pronoun in
                HStack(spacing: 6) {
                    Text(pronoun.displayLabel)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.60))
                        .frame(width: 96, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    ForEach(engine.selectedVerbs) { verb in
                        if let (cell, idx) = cellAndIndex(pronoun: pronoun, verb: verb) {
                            cellView(cell: cell, index: idx)
                                .frame(maxWidth: .infinity)
                                .frame(height: isLandscape ? 40 : 64)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func cellView(cell: GameCell, index: Int) -> some View {
        let active = isCellActive(cell)
        let opacity = shouldHideCell(cell) ? 0.1 : 1.0

        if isReview && cell.state == .missed && engine.reviewActiveCellIndex != index {
            Button {
                engine.retryCell(at: index)
            } label: {
                MatrixCellView(cell: cell, isActive: active, timerProgress: 1.0)
            }
            .buttonStyle(.plain)
            .opacity(opacity)
        } else if isReview && engine.reviewActiveCellIndex == index {
            MatrixCellView(cell: cell, isActive: true, timerProgress: 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(GameColors.gold, lineWidth: 2)
                        .opacity(engine.isListening ? 1 : 0)
                )
                .onTapGesture { engine.cancelRetry() }
                .opacity(opacity)
        } else {
            MatrixCellView(cell: cell, isActive: active, timerProgress: active ? timerProgress : 1.0)
                .opacity(opacity)
        }
    }

    private func shouldHideCell(_ cell: GameCell) -> Bool {
        guard isReview, engine.hideCorrect else { return false }
        return cell.state == .correct
    }

    // MARK: - Listening indicator (full-width bottom banner)

    private var listeningIndicator: some View {
        let isProcessing = engine.isPostProcessing && !engine.isListening
        return VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: isProcessing ? "waveform" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isProcessing ? GameColors.gold : GameColors.rojo)
                    .shadow(color: (isProcessing ? GameColors.gold : GameColors.rojo).opacity(0.8), radius: 6)

                Text(isProcessing ? "PROCESSING…" : "LISTENING…")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(2)

                Spacer()

                Circle()
                    .fill(isProcessing ? GameColors.gold : GameColors.rojo)
                    .frame(width: 10, height: 10)
                    .shadow(color: (isProcessing ? GameColors.gold : GameColors.rojo).opacity(0.9), radius: 6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.06, green: 0.06, blue: 0.14).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke((isProcessing ? GameColors.gold : GameColors.rojo).opacity(0.35), lineWidth: 1.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Helpers

    private func cellAndIndex(pronoun: Pronoun, verb: Verb) -> (GameCell, Int)? {
        guard let r = engine.round else { return nil }
        guard let idx = r.cells.firstIndex(where: { $0.pronoun == pronoun && $0.verb.infinitive == verb.infinitive }) else { return nil }
        return (r.cells[idx], idx)
    }

    private func isCellActive(_ cell: GameCell) -> Bool {
        guard let active = engine.currentActiveCell else { return false }
        return active.id == cell.id
    }

    private var timerProgress: Double {
        engine.timeRemaining / engine.timerSeconds
    }
}

// MARK: - VerbChip

private struct VerbChip: View {
    let verb: Verb

    var body: some View {
        VStack(spacing: 3) {
            Text(verb.infinitive)
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(.black.opacity(0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .white.opacity(0.15), radius: 2)

            if verb.joker {
                Text(verb.jokerKind == .fullyIrregular ? "IRREG" : "STEM")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.65))
                    .tracking(1)
            } else {
                Text("-\(verb.type.rawValue)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            verb.joker ? GameColors.jokerBadgeGradient : GameColors.verbBadgeGradient
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: (verb.joker ? GameColors.coral : GameColors.gold).opacity(0.40), radius: 6, y: 3)
    }
}
