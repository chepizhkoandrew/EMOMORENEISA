import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct EMOMORENEISAApp: App {
    @State private var authState = AuthState.shared
    @State private var pendingInvite = PendingInvite.shared

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "353195660969-ff6luandfvauj7odempe0k2imsnh98k5.apps.googleusercontent.com"
        )
    }

    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            LocalStudentProfile.self,
            LocalChatSession.self,
            LocalChatMessage.self,
            ParrotPhrase.self,
            MemoryCard.self,
            StreetAnnotation.self,
            VerbAttempt.self,
            SavedSong.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(authState)
                .modelContainer(Self.modelContainer)
                .task { await authState.restoreSession() }
                // The app is dark-themed everywhere, but without this,
                // fullScreenCover/sheet presentations can show a flash of the
                // system's light-mode backdrop for a frame before the
                // presented view's own background paints.
                .preferredColorScheme(.dark)
                // Friend-invite universal links (professormadrid.com/invite/<token>).
                // Cold launches deliver them via NSUserActivity, warm ones via
                // onOpenURL; PendingInvite persists the token so it survives the
                // whole signup flow and claims once the user is signed in.
                .onOpenURL { url in
                    PendingInvite.shared.capture(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        PendingInvite.shared.capture(url)
                    }
                }
                .onChange(of: authState.isSignedIn) { _, signedIn in
                    if signedIn { Task { await PendingInvite.shared.claimIfPossible() } }
                }
                .alert(
                    inviteAlertTitle,
                    isPresented: Binding(
                        get: { pendingInvite.lastOutcome != nil },
                        set: { if !$0 { pendingInvite.lastOutcome = nil } }
                    )
                ) {
                    Button(L("OK")) { pendingInvite.lastOutcome = nil }
                } message: {
                    Text(inviteAlertMessage)
                }
        }
    }

    private var inviteAlertTitle: String {
        switch pendingInvite.lastOutcome {
        case .becameFriends: return L("You're friends now!")
        case .alreadyFriends: return L("Already friends")
        case .deadLink: return L("Invite unavailable")
        case nil: return ""
        }
    }

    private var inviteAlertMessage: String {
        switch pendingInvite.lastOutcome {
        case .becameFriends(let name):
            return L("You and %@ are now learning Spanish together.", name)
        case .alreadyFriends(let name):
            return L("You and %@ are already friends.", name)
        case .deadLink:
            return L("This invite link is no longer active.")
        case nil:
            return ""
        }
    }
}
