import SwiftUI

/// Two-step song creation flow ("Remember with Music"). Step 1 picks genre +
/// length, step 2 collects words/lyrics and generates. The pages live in a
/// page-style TabView so the user can swipe back and forth between the steps;
/// the shared BackButton mirrors the rest of the app.
struct MusicFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = MusicFlowModel()
    @State private var page = 0

    var body: some View {
        ZStack {
            GameBackground()
            DreamParticlesView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            TabView(selection: $page) {
                MusicSetupView(model: model) {
                    withAnimation { page = 1 }
                }
                .tag(0)

                MusicLyricsView(model: model)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay(alignment: .topLeading) {
            BackButton {
                if page == 1 {
                    withAnimation { page = 0 }
                } else {
                    dismiss()
                }
            }
            .padding(.leading, HomeLayout.hPadding)
            .padding(.top, 8)
        }
        .overlay(alignment: .top) {
            stepDots
                .padding(.top, 16)
        }
        .onChange(of: page) { _, _ in
            hideKeyboard()
        }
        .onDisappear {
            model.tearDown()
        }
    }

    private var stepDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.yellow : Color.white.opacity(0.3))
                    .frame(width: i == page ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35), value: page)
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Step 1: genre + length

struct MusicSetupView: View {
    @Bindable var model: MusicFlowModel
    let onContinue: () -> Void

    @State private var showGenrePicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Create a Song"))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(L("Pick a genre and a length — then tell me what to sing about."))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 64)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Genre"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    ChipFlowLayout(spacing: 8) {
                        ForEach(featuredGenres, id: \.self) { genre in
                            genreChip(genre)
                        }
                        moreGenresChip
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Song length"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    ForEach(SongLength.allCases) { option in
                        lengthRow(option)
                    }
                }

                continueButton
                    .padding(.top, 6)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, HomeLayout.hPadding)
        }
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(selected: $model.selectedGenre)
        }
    }

    /// Featured chips, plus the current selection when it came from the full
    /// catalog or a custom entry (so it never looks unselected).
    private var featuredGenres: [String] {
        var names = MusicGenreCatalog.featured
        if let sel = model.selectedGenre, !names.contains(sel) {
            names.insert(sel, at: 0)
        }
        return names
    }

    private func genreChip(_ genre: String) -> some View {
        let isSelected = model.selectedGenre == genre
        return Button {
            model.selectedGenre = isSelected ? nil : genre
        } label: {
            Text(genre)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Color.yellow : Color.white.opacity(0.09))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var moreGenresChip: some View {
        Button {
            showGenrePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                Text(L("More genres…"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.yellow.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.yellow.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func lengthRow(_ option: SongLength) -> some View {
        let isSelected = model.length == option
        return Button {
            model.length = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .yellow : .white.opacity(0.35))

                VStack(alignment: .leading, spacing: 3) {
                    Text(L(option.titleKey))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(L(option.subtitleKey))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Image("dream_hotdog")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("\(option.treatCost)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.yellow.opacity(0.13) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.yellow.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: 8) {
                Text(L("Continue"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(model.canContinue ? Color.yellow : Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canContinue)
    }
}

// MARK: - Full genre catalog sheet

struct GenrePickerSheet: View {
    @Binding var selected: String?
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var customGenre = ""

    private var results: [MusicGenre] { MusicGenreCatalog.search(query) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L("Your own genre…"), text: $customGenre)
                            .autocorrectionDisabled()
                        Button(L("Use")) {
                            let g = customGenre.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !g.isEmpty else { return }
                            selected = g
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .disabled(customGenre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                ForEach(groupedResults, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.genres) { genre in
                            Button {
                                selected = genre.name
                                dismiss()
                            } label: {
                                HStack {
                                    Text(genre.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selected == genre.name {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.yellow)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: L("Search genres"))
            .navigationTitle(L("All genres"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private var groupedResults: [(category: String, genres: [MusicGenre])] {
        var order: [String] = []
        var buckets: [String: [MusicGenre]] = [:]
        for genre in results {
            if buckets[genre.category] == nil { order.append(genre.category) }
            buckets[genre.category, default: []].append(genre)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

// MARK: - Wrapping chip layout

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
