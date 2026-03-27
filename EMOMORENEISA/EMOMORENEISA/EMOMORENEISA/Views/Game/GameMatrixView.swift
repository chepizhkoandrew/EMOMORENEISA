import SwiftUI

struct GameMatrixView: View {
    @EnvironmentObject var engine: GameEngine

    private var isReview: Bool { engine.phase == .review }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                guidanceBanner
                headerRow
                Divider().background(Color.white.opacity(0.15))
                matrixBody
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if engine.isListening && !isReview {
                listeningIndicator
            }
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
                    Text(isReview ? "NEW ROUND" : "STOP")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Spacer()

            if isReview {
                reviewControls
            } else if engine.isPostProcessing {
                Text("PROCESSING…")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.6))
                    .shadow(color: .yellow.opacity(0.4), radius: 4)
            }
        }
        .padding(.bottom, 4)
    }

    private var reviewControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { engine.hideCorrect.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.hideCorrect ? "eye.slash" : "eye")
                    Text(engine.hideCorrect ? "SHOW ALL" : "HIDE CORRECT")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(engine.hideCorrect ? .yellow : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Button {
                engine.enterResults()
            } label: {
                Text("SUMMARY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.07))
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
                    .transition(.opacity)
            } else if let result = engine.lastResult {
                resultBanner(result: result)
                    .transition(.opacity)
            } else if isReview {
                reviewIdleBanner
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: engine.currentActiveCell?.id)
        .animation(.easeInOut(duration: 0.2), value: engine.lastResult?.pronoun)
        .animation(.easeInOut(duration: 0.2), value: isReview)
    }

    private func activeBanner(cell: GameCell) -> some View {
        let (knownStem, endingBlanks) = stemAndBlanks(infinitive: cell.verb.infinitive, conjugation: cell.expectedConjugation)
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(cell.pronoun.displayLabel.uppercased())
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.7), radius: 8)
                    .shadow(color: .yellow.opacity(0.3), radius: 16)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if !knownStem.isEmpty {
                        Text(knownStem)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .white.opacity(0.4), radius: 6)
                    }
                    Text(endingBlanks.isEmpty ? "_" : endingBlanks)
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.22))
                        .tracking(3)
                }
            }

            if !engine.liveTranscript.isEmpty {
                Text("« \(engine.liveTranscript) »")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.15), value: engine.liveTranscript)
            } else {
                Text(isReview ? "LISTENING FOR RETRY…" : "LISTENING…")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 80)
    }

    private func resultBanner(result: GameEngine.LastResult) -> some View {
        let color: Color = result.correct ? .green : .red
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.pronoun.uppercased())
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundColor(color.opacity(0.65))

                Text(result.conjugation)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.6), radius: 8)
            }

            if !result.userTranscript.isEmpty && !result.correct {
                Text("you said: \"\(result.userTranscript)\"")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.red.opacity(0.55))
                    .lineLimit(1)
            } else if result.correct {
                Text("✓ CORRECT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.65))
                    .shadow(color: .green.opacity(0.5), radius: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 80)
    }

    private var reviewIdleBanner: some View {
        let missedCount = engine.round?.cells.filter { $0.state == .missed }.count ?? 0
        return VStack(spacing: 4) {
            Text(missedCount == 0 ? "ALL CORRECT" : "TAP A RED CELL TO RETRY")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(missedCount == 0 ? .green : .white.opacity(0.55))
                .shadow(color: missedCount == 0 ? .green.opacity(0.6) : .clear, radius: 8)

            if missedCount > 0 {
                Text("\(missedCount) REMAINING")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.red.opacity(0.6))
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 80)
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("")
                .frame(width: 76)

            ForEach(Array(engine.selectedVerbs.enumerated()), id: \.offset) { _, verb in
                VStack(spacing: 2) {
                    Text(verb.infinitive)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 6)
                    if verb.joker {
                        Text(verb.jokerKind == .fullyIrregular ? "IRREG" : "STEM")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                            .tracking(1)
                    } else {
                        Text("-\(verb.type.rawValue)")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Matrix

    private var matrixBody: some View {
        VStack(spacing: 4) {
            ForEach(Pronoun.allCases) { pronoun in
                HStack(spacing: 6) {
                    Text(pronoun.displayLabel)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 76, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    ForEach(engine.selectedVerbs) { verb in
                        if let (cell, idx) = cellAndIndex(pronoun: pronoun, verb: verb) {
                            cellView(cell: cell, index: idx)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 2).opacity(engine.isListening ? 1 : 0))
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

    // MARK: - Listening indicator

    private var listeningIndicator: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.8), radius: 4)
                Text("LISTENING…")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.bottom, 32)
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
