import Foundation
import UserNotifications

/// Local-notification scheduler for Loro Memorize (spec §14). Phase 1 ships N1:
/// a single batched daily reminder with the aggregate due count. Audio/SRS work
/// is unaffected — this only schedules `UNNotificationRequest`s.
@MainActor
final class MemoryCardNotificationService {
    static let shared = MemoryCardNotificationService()
    private init() {}

    private let n1Identifier = "loro.memorize.n1.daily"
    private let authRequestedKey = "loro.memorize.notifAuthRequested"

    @AppStorageBacked("loro.reminderHour", default: 19) private var reminderHour: Int
    @AppStorageBacked("loro.notifyDaily", default: true) private var notifyDaily: Bool

    /// Request authorization once (Phase 1: on first Hub visit; priming after the
    /// first Microchip moment is a Phase 4 refinement, spec §14.2).
    func requestAuthorizationIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: authRequestedKey) else { return }
        defaults.set(true, forKey: authRequestedKey)
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Refresh the N1 schedule using the current due count. Called on Hub
    /// appearance / app foreground. Removes N1 when nothing is due.
    func refresh(dueCount: Int) async {
        await requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: [n1Identifier])
        // Respect the user's "Daily reminder" toggle (spec §16.1): if disabled,
        // cancel N1 above and schedule nothing.
        guard notifyDaily else { return }
        guard dueCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Seagull Steven is waiting"
        content.body = dueCount == 1
            ? "1 word is ready to practice."
            : "\(dueCount) words are ready to practice."
        content.sound = .default
        content.userInfo = ["deepLink": "loro-memorize"]

        var date = DateComponents()
        date.hour = reminderHour
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: n1Identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

/// Minimal `UserDefaults`-backed property wrapper (the views use SwiftUI's
/// `@AppStorage`; this service is not a View, so it reads the same key directly).
@propertyWrapper
struct AppStorageBacked<Value> {
    let key: String
    let defaultValue: Value

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get { (UserDefaults.standard.object(forKey: key) as? Value) ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
