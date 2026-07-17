import SwiftUI
import SwiftData

/// "Words queue" settings — the SRS scheduling, capacity, and notification
/// parameters for Seagull Steven's memory queue (spec §16.1). Persisted via
/// `@AppStorage`; `maxNearTermLoad` feeds Gate 4 and the "This week" capacity
/// ceiling.
///
/// This is a *pushable* page: it lives inside `SettingsHubView`'s NavigationStack
/// (Settings → Words queue), so it owns no NavigationStack or Done button of its
/// own — the hub's chrome handles navigation. Language moved out to User
/// settings (`AppSettingsView`).
struct WordsQueueSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("loro.dailyNewLimit") private var dailyNewLimit: Int = 5
    @AppStorage("loro.maxActiveLearning") private var maxActiveLearning: Int = 20
    @AppStorage("loro.maxNearTermLoad") private var maxNearTermLoad: Int = 40
    @AppStorage("loro.sessionSizeCap") private var sessionSizeCap: Int = 20
    @AppStorage("loro.autoAdvance") private var autoAdvance: Bool = true
    @AppStorage("loro.reminderHour") private var reminderHour: Int = 19
    @AppStorage("loro.notifyDaily") private var notifyDaily: Bool = true
    @AppStorage("loro.vacationMode") private var vacationMode: Bool = false

    @State private var confirmReset = false

    var body: some View {
        ZStack {
            AppBackground()

            Form {
                Section(L("Capacity")) {
                    stepperRow(L("New words per day"), value: $dailyNewLimit, range: 1...20)
                    stepperRow(L("Max active learning"), value: $maxActiveLearning, range: 5...50)
                    stepperRow(L("Weekly play ceiling"), value: $maxNearTermLoad, range: 10...200, step: 5)
                }

                Section(L("Session")) {
                    stepperRow(L("Session size cap"), value: $sessionSizeCap, range: 5...50)
                    Toggle(L("Auto-advance words"), isOn: $autoAdvance)
                }

                Section(L("Reminders")) {
                    Toggle(L("Daily reminder"), isOn: $notifyDaily)
                    if notifyDaily {
                        Stepper(L("Reminder hour: %d:00", reminderHour), value: $reminderHour, in: 6...23)
                    }
                }

                Section(L("Vacation")) {
                    Toggle(L("Pause all scheduling"), isOn: $vacationMode)
                        .onChange(of: vacationMode) { _, paused in
                            setAllPaused(paused)
                        }
                }

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text(L("Reset all progress"))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .tint(.yellow)
        .navigationTitle(L("Words queue"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert(L("Reset all progress?"), isPresented: $confirmReset) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Reset"), role: .destructive) { resetAll() }
        } message: {
            Text(L("This permanently deletes every memory card. Seagull Steven will forget all his words. This cannot be undone."))
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        Stepper("\(title): \(value.wrappedValue)", value: value, in: range, step: step)
    }

    private func setAllPaused(_ paused: Bool) {
        let service = MemoryCardService(context: modelContext)
        let all = (try? modelContext.fetch(FetchDescriptor<MemoryCard>())) ?? []
        for card in all where !card.isArchived {
            service.setPaused(card, paused)
        }
    }

    private func resetAll() {
        let all = (try? modelContext.fetch(FetchDescriptor<MemoryCard>())) ?? []
        for card in all { modelContext.delete(card) }
        try? modelContext.save()
    }
}
